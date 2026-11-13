/*
 * btctl: Bluetooth from the command line, for the iOS 27 root without Settings (AirPods pairing for LibrePods,
 * 2026-11-13; docs/features/bluetooth.md). A client of bluetoothd through MobileBluetooth.framework's C API, the one
 * BluetoothManager.framework (Settings) wraps; every function is found by dlsym at run time.
 *   btctl power on|off|status         module power (status: power, discoverable, connectable, address, paired count)
 *   btctl discoverable on|off
 *   btctl scan [SECS] [-c|-l]         classic inquiry (name, address, class, type) and LE adverts via CoreBluetooth
 *                                     (name, RSSI, Apple data); -c classic only, -l LE only; default 15 s
 *   btctl paired                      paired devices
 *   btctl pair ADDR [SECS]            scan until ADDR shows up, connect, accept SSP (numeric comparison or just
 *                                     works) and legacy PIN 0000; prints each step; default 60 s
 *   btctl connect ADDR [MASK]         connect services (default mask 0xffffd7bf, as -[BluetoothManager connectDevice:])
 *   btctl disconnect ADDR | unpair ADDR
 *   btctl wait-pair [SECS]            connectable + discoverable, accept incoming pairing requests; default 120 s
 * Env: BTCTL_NOLE=1 skips the CoreBluetooth LE scan (same as -c).
 * Signatures checked against the 24B156 (27.2.1) cache: MobileBluetooth's exports and how BluetoothManager calls
 * them (booleans are passed as -1/0, as BluetoothManager does). Signed with btctl-ents.plist: bluetoothd gives an
 * MBFramework session access only with com.apple.bluetooth.internal (level 2) or .system (level 1).
 */
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/message.h>

typedef void *BTSession;
typedef uint64_t BTHandle;	/* local device, device, agent: 64-bit ids */

struct session_cbs {
	void (*event)(BTSession s, int event, int result, void *ud);
};
struct local_cbs {
	void (*status)(BTHandle local, int event, int result, void *ud);
	void *unused[2];
};
struct discovery_cbs {
	void (*status)(BTHandle agent, int status, BTHandle dev, int result, void *ud);
	void (*event)(BTHandle agent, int event, BTHandle dev, uint32_t attrs, void *ud);
};
struct pairing_cbs {
	void (*status)(BTHandle agent, int event, BTHandle dev, int result, void *ud);
	void (*pincode)(BTHandle agent, BTHandle dev, int arg, void *ud);
	void (*authorization)(BTHandle agent, BTHandle dev, int arg, void *ud);
	void (*user_confirm)(BTHandle agent, BTHandle dev, uint32_t value, int numeric, void *ud);
	void (*passkey)(BTHandle agent, BTHandle dev, uint32_t passkey, void *ud);
	void (*oob_ready)(BTHandle agent, void *a1, void *a2, void *ud);
};
typedef void (*service_cb)(BTHandle dev, uint32_t services, int type, int event, int result, void *ud);

#define MBFN(X) \
	X(int, BTSessionAttachWithQueue, (const char *, struct session_cbs *, void *, dispatch_queue_t)) \
	X(int, BTSessionDetachWithQueue, (BTSession *)) \
	X(int, BTLocalDeviceGetDefault, (BTSession, BTHandle *)) \
	X(int, BTLocalDeviceAddCallbacks, (BTHandle, struct local_cbs *, void *)) \
	X(int, BTLocalDeviceRemoveCallbacks, (BTHandle, struct local_cbs *)) \
	X(int, BTLocalDeviceGetModulePower, (BTHandle, int, int *)) \
	X(int, BTLocalDeviceSetModulePower, (BTHandle, int, int)) \
	X(int, BTLocalDeviceGetDiscoverable, (BTHandle, int *)) \
	X(int, BTLocalDeviceSetDiscoverable, (BTHandle, int)) \
	X(int, BTLocalDeviceGetConnectable, (BTHandle, int *)) \
	X(int, BTLocalDeviceSetConnectable, (BTHandle, int)) \
	X(int, BTLocalDeviceGetAddressString, (BTHandle, char *, size_t)) \
	X(int, BTLocalDeviceGetPairedDevices, (BTHandle, BTHandle *, size_t *, size_t)) \
	X(int, BTDiscoveryAgentCreate, (BTSession, struct discovery_cbs *, void *, BTHandle *)) \
	X(int, BTDiscoveryAgentStartScan, (BTHandle, int, uint32_t)) \
	X(int, BTDiscoveryAgentStopScan, (BTHandle)) \
	X(int, BTDiscoveryAgentDestroy, (BTHandle *)) \
	X(int, BTPairingAgentCreate, (BTSession, struct pairing_cbs *, void *, BTHandle *)) \
	X(int, BTPairingAgentStart, (BTHandle)) \
	X(int, BTPairingAgentStop, (BTHandle)) \
	X(int, BTPairingAgentDestroy, (BTHandle *)) \
	X(int, BTPairingAgentAcceptSSP, (BTHandle, BTHandle, int)) \
	X(int, BTPairingAgentSetPincode, (BTHandle, BTHandle, const char *)) \
	X(int, BTPairingAgentDeletePairedDevice, (BTHandle, BTHandle)) \
	X(int, BTServiceAddCallbacks, (BTSession, service_cb, void *)) \
	X(int, BTServiceRemoveCallbacks, (BTSession, service_cb)) \
	X(int, BTDeviceAddressFromString, (const char *, uint8_t *)) \
	X(int, BTDeviceFromAddress, (BTSession, const uint8_t *, BTHandle *)) \
	X(int, BTDeviceGetAddressString, (BTHandle, char *, size_t)) \
	X(int, BTDeviceGetName, (BTHandle, char *, size_t)) \
	X(int, BTDeviceGetDefaultName, (BTHandle, char *, size_t)) \
	X(int, BTDeviceGetDeviceClass, (BTHandle, uint32_t *)) \
	X(int, BTDeviceGetDeviceType, (BTHandle, int *)) \
	X(int, BTDeviceGetConnectedServices, (BTHandle, uint32_t *)) \
	X(int, BTDeviceGetPairingStatus, (BTHandle, int *)) \
	X(int, BTDeviceConnectServices, (BTHandle, uint32_t)) \
	X(int, BTDeviceDisconnect, (BTHandle))
#define DECL(ret, name, args) static ret(*name) args;
MBFN(DECL)

#define POWER_MODULE_BT 1	/* -[BluetoothManager setPowered:] / powerState */
#define ALL_SERVICES 0xffffd7bfu	/* -[BluetoothManager connectDevice:] and scanForServices: */

static BTSession session;
static BTHandle local, pairing, discovery, target;
static int attached, attach_event = -1, attach_result, scan_done, pair_done, pair_result, connect_done;
static NSMutableArray *seen;	/* classic: NSNumber handles already printed */
static double t0;

static double now(void)
{
	return [NSDate timeIntervalSinceReferenceDate];
}

static void stamp(void)
{
	printf("[%6.2f] ", now() - t0);
}

/* Run the main queue/run loop until *flag is set or SECS pass; returns *flag. */
static int run_until(double secs, int *flag)
{
	double end = now() + secs;
	while ((flag == NULL || !*flag) && now() < end)
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
	fflush(stdout);
	return flag ? *flag : 0;
}

static const char *major_class(uint32_t cod)
{
	static const char *n[] = { "misc", "computer", "phone", "network", "audio/video", "peripheral", "imaging",
				   "wearable", "toy", "health" };
	unsigned m = (cod >> 8) & 0x1f;
	return m < sizeof(n) / sizeof(n[0]) ? n[m] : (m == 0x1f ? "uncategorized" : "?");
}

static void describe(BTHandle dev, char *out, size_t len)
{
	char addr[64] = "", name[256] = "";
	uint32_t cod = 0, svc = 0;
	int type = -1, paired = 0;
	BTDeviceGetAddressString(dev, addr, sizeof(addr));
	if (BTDeviceGetName(dev, name, sizeof(name)) != 0 || !name[0])
		BTDeviceGetDefaultName(dev, name, sizeof(name));
	BTDeviceGetDeviceClass(dev, &cod);
	BTDeviceGetDeviceType(dev, &type);
	BTDeviceGetConnectedServices(dev, &svc);
	BTDeviceGetPairingStatus(dev, &paired);
	snprintf(out, len, "%s \"%s\" class 0x%06x (%s) type %d paired %d services 0x%x", addr[0] ? addr : "?", name,
		 cod, major_class(cod), type, paired, svc);
}

/* ---- callbacks (main queue) ---- */

static void session_event(BTSession s, int event, int result, void *ud)
{
	stamp();
	printf("session event %d result %d\n", event, result);
	if (event == 0 && result == 0) {	/* attached (BluetoothManager's _btSessionEventCallback) */
		session = s;
		attached = 1;
	}
	attach_event = event;
	attach_result = result;
}

static void local_status(BTHandle l, int event, int result, void *ud)
{
	stamp();
	printf("local device event %d%s result %d\n", event, event == 0 ? " (power changed)" : "", result);
}

static void discovery_status(BTHandle agent, int status, BTHandle dev, int result, void *ud)
{
	stamp();
	printf("discovery status %d result %d\n", status, result);
	if (status == 1)	/* BluetoothManager posts BluetoothDiscoveryStoppedNotification on 1 */
		scan_done = 1;
}

static void discovery_event(BTHandle agent, int event, BTHandle dev, uint32_t attrs, void *ud)
{
	char d[512];
	if (event != 0)	/* 1 = removed */
		return;
	describe(dev, d, sizeof(d));
	NSNumber *k = @(dev);
	stamp();
	printf("%s classic %s attrs 0x%x\n", [seen containsObject:k] ? "~" : "+", d, attrs);
	[seen addObject:k];
	if (target) {
		char a[64] = "", t[64] = "";
		BTDeviceGetAddressString(dev, a, sizeof(a));
		BTDeviceGetAddressString(target, t, sizeof(t));
		if (a[0] && !strcasecmp(a, t))
			scan_done = 1;
	}
}

static void pairing_status(BTHandle agent, int event, BTHandle dev, int result, void *ud)
{
	char d[512] = "(none)";
	if (dev != 0xffff0001)	/* no device (BluetoothManager's pairingAgentStatusEventCallback) */
		describe(dev, d, sizeof(d));
	stamp();
	printf("pairing event %d%s result %d device %s\n", event, event == 3 ? " (complete)" : "", result, d);
	if (event == 3) {
		pair_done = 1;
		pair_result = result;
	}
}

static void pairing_pincode(BTHandle agent, BTHandle dev, int arg, void *ud)
{
	char d[512];
	describe(dev, d, sizeof(d));
	stamp();
	printf("PIN request (legacy) from %s: answering 0000 -> %d\n", d, BTPairingAgentSetPincode(agent, dev, "0000"));
}

static void pairing_authorization(BTHandle agent, BTHandle dev, int arg, void *ud)
{
	stamp();
	printf("authorization request (arg %d): ignored, as BluetoothManager does\n", arg);
}

static void pairing_confirm(BTHandle agent, BTHandle dev, uint32_t value, int numeric, void *ud)
{
	char d[512];
	describe(dev, d, sizeof(d));
	stamp();
	if (numeric)
		printf("SSP numeric comparison %06u from %s: accepting", value, d);
	else
		printf("SSP confirmation (just works) from %s: accepting", d);
	printf(" -> %d\n", BTPairingAgentAcceptSSP(agent, dev, 0));
}

static void pairing_passkey(BTHandle agent, BTHandle dev, uint32_t passkey, void *ud)
{
	char d[512];
	describe(dev, d, sizeof(d));
	stamp();
	printf("passkey display %06u for %s (type it on the other device)\n", passkey, d);
}

static void pairing_oob(BTHandle agent, void *a1, void *a2, void *ud)
{
}

static void service_event(BTHandle dev, uint32_t services, int type, int event, int result, void *ud)
{
	char d[512];
	describe(dev, d, sizeof(d));
	stamp();
	/* type 0 event 11 = connect result, type 1 event 12 = disconnect result (BluetoothManager's handling) */
	printf("service 0x%x type %d event %d result %d%s %s\n", services, type, event, result,
	       type == 0 && event == 11 ? (result ? " CONNECT FAILED" : " CONNECTED") :
	       type == 1 && event == 12 ? " DISCONNECTED" : "", d);
	if (dev == target && ((type == 0 && event == 11) || (type == 1 && event == 12)))
		connect_done = 1;
}

static struct session_cbs scbs = { session_event };
static struct local_cbs lcbs = { local_status };
static struct discovery_cbs dcbs = { discovery_status, discovery_event };
static struct pairing_cbs pcbs = { pairing_status, pairing_pincode, pairing_authorization, pairing_confirm,
				   pairing_passkey, pairing_oob };

/* ---- LE scan through CoreBluetooth (public API, RSSI and advertisement data) ---- */

@interface NSObject (BTCtlCB)
- (id)initWithDelegate:(id)d queue:(dispatch_queue_t)q options:(NSDictionary *)o;
- (NSInteger)state;
- (void)scanForPeripheralsWithServices:(NSArray *)s options:(NSDictionary *)o;
- (void)stopScan;
@end

@interface BTCtlLE : NSObject
@property (strong) id central;
@property (strong) NSMutableDictionary *found;
@end

@implementation BTCtlLE
- (void)centralManagerDidUpdateState:(id)c
{
	static const char *st[] = { "unknown", "resetting", "unsupported", "unauthorized", "powered off", "powered on" };
	NSInteger s = [c state];
	stamp();
	printf("LE: CoreBluetooth state %ld (%s)\n", (long)s, s >= 0 && s <= 5 ? st[s] : "?");
	if (s == 5)
		[c scanForPeripheralsWithServices:nil options:@{ @"kCBScanOptionAllowDuplicates" : @NO }];
}

- (void)centralManager:(id)c didDiscoverPeripheral:(id)p advertisementData:(NSDictionary *)ad RSSI:(NSNumber *)rssi
{
	NSString *uuid = [[p valueForKey:@"identifier"] UUIDString];	/* CBPeripheral properties via KVC */
	if (uuid == nil || self.found[uuid])
		return;
	self.found[uuid] = rssi;
	NSString *name = ad[@"kCBAdvDataLocalName"] ?: [p valueForKey:@"name"] ?: @"";
	NSData *m = ad[@"kCBAdvDataManufacturerData"];
	NSMutableString *hex = [NSMutableString string];
	const uint8_t *b = m.bytes;
	for (NSUInteger i = 0; i < m.length && i < 27; i++)
		[hex appendFormat:@"%02x", b[i]];
	stamp();
	printf("+ LE %s \"%s\" rssi %d%s%s%s\n", uuid.UTF8String, name.UTF8String, rssi.intValue,
	       m.length ? " mfr " : "", hex.UTF8String,
	       m.length >= 3 && b[0] == 0x4c && b[1] == 0 ? (b[2] == 0x07 ? " (Apple proximity pairing)" : " (Apple)") : "");
}
@end

/* ---- setup ---- */

static int load(void)
{
	void *h = dlopen("/System/Library/PrivateFrameworks/MobileBluetooth.framework/MobileBluetooth", RTLD_NOW);
	if (!h) {
		fprintf(stderr, "btctl: %s\n", dlerror());
		return -1;
	}
#define LOAD(ret, name, args) \
	if (!(name = (ret(*) args)dlsym(h, #name))) { \
		fprintf(stderr, "btctl: MobileBluetooth has no %s\n", #name); \
		return -1; \
	}
	MBFN(LOAD)
	return 0;
}

static int attach(void)
{
	int r = BTSessionAttachWithQueue("btctl", &scbs, NULL, dispatch_get_main_queue());
	if (r) {	/* 9: MobileGestalt "bluetooth" false or no IOService "marconi-bt"/"bluetooth" */
		fprintf(stderr, "btctl: BTSessionAttachWithQueue -> %d\n", r);
		return -1;
	}
	if (!run_until(10, &attached)) {
		fprintf(stderr, "btctl: no session from bluetoothd in 10 s (last event %d result %d; entitlements?)\n",
			attach_event, attach_result);
		return -1;
	}
	if ((r = BTLocalDeviceGetDefault(session, &local))) {
		fprintf(stderr, "btctl: BTLocalDeviceGetDefault -> %d\n", r);
		return -1;
	}
	BTLocalDeviceAddCallbacks(local, &lcbs, NULL);
	return 0;
}

static void detach(void)
{
	if (discovery) {
		BTDiscoveryAgentStopScan(discovery);
		BTDiscoveryAgentDestroy(&discovery);
	}
	if (pairing) {
		BTPairingAgentStop(pairing);
		BTPairingAgentDestroy(&pairing);
	}
	if (local)
		BTLocalDeviceRemoveCallbacks(local, &lcbs);
	if (session) {
		BTServiceRemoveCallbacks(session, service_event);
		BTSessionDetachWithQueue(&session);
	}
}

static int power_state(void)
{
	int p = 0;
	BTLocalDeviceGetModulePower(local, POWER_MODULE_BT, &p);
	return p;
}

static const char *power_name(int p)
{
	return p == -1 ? "on" : p == 0 ? "off" : p == (int)0xcafebabe ? "busy (0xcafebabe)" : "?";
}

static int power(int on)
{
	int r = BTLocalDeviceSetModulePower(local, POWER_MODULE_BT, on ? -1 : 0);
	stamp();
	printf("set power %s -> %d\n", on ? "on" : "off", r);
	for (int i = 0; i < 100 && power_state() != (on ? -1 : 0); i++)
		run_until(0.1, NULL);
	stamp();
	printf("power: %s (0x%x)\n", power_name(power_state()), power_state());
	return power_state() == (on ? -1 : 0) ? 0 : 1;
}

static int ensure_power(void)
{
	return power_state() == -1 ? 0 : power(1);
}

static int lookup(const char *addr, BTHandle *dev)
{
	uint8_t a[8] = { 0 };
	int r = BTDeviceAddressFromString(addr, a);
	if (r) {
		fprintf(stderr, "btctl: bad address %s (%d)\n", addr, r);
		return -1;
	}
	if ((r = BTDeviceFromAddress(session, a, dev))) {
		fprintf(stderr, "btctl: BTDeviceFromAddress %s -> %d\n", addr, r);
		return -1;
	}
	return 0;
}

static int start_pairing_agent(void)
{
	int r = BTPairingAgentCreate(session, &pcbs, NULL, &pairing);
	if (!r)
		r = BTPairingAgentStart(pairing);
	stamp();
	printf("pairing agent started -> %d\n", r);
	return r;
}

static int start_scan(void)
{
	int r = BTDiscoveryAgentCreate(session, &dcbs, NULL, &discovery);
	if (!r)
		r = BTDiscoveryAgentStartScan(discovery, 0, ALL_SERVICES);
	stamp();
	printf("classic scan started -> %d\n", r);
	return r;
}

/* ---- commands ---- */

static int cmd_status(void)
{
	char addr[64] = "";
	int disc = 0, conn = 0;
	size_t n = 0;
	BTHandle devs[256];
	BTLocalDeviceGetAddressString(local, addr, sizeof(addr));
	BTLocalDeviceGetDiscoverable(local, &disc);
	BTLocalDeviceGetConnectable(local, &conn);
	BTLocalDeviceGetPairedDevices(local, devs, &n, 256);
	printf("power %s (0x%x), discoverable %d, connectable %d, address %s, paired %zu\n", power_name(power_state()),
	       power_state(), disc != 0, conn != 0, addr, n);
	return 0;
}

static int cmd_discoverable(int on)
{
	int r, d = 0;
	if (on && ensure_power())
		return 1;
	r = BTLocalDeviceSetDiscoverable(local, on ? -1 : 0);
	run_until(0.5, NULL);
	BTLocalDeviceGetDiscoverable(local, &d);
	printf("set discoverable %s -> %d; discoverable now %d (bluetoothd may end it when btctl exits; wait-pair keeps "
	       "it on)\n", on ? "on" : "off", r, d != 0);
	return r != 0;
}

static int cmd_scan(double secs, int classic, int le)
{
	BTCtlLE *del = nil;
	if (ensure_power())
		return 1;
	seen = [NSMutableArray array];
	if (classic && start_scan())
		classic = 0;
	if (le) {
		dlopen("/System/Library/Frameworks/CoreBluetooth.framework/CoreBluetooth", RTLD_NOW);
		Class c = NSClassFromString(@"CBCentralManager");
		if (c) {
			del = [BTCtlLE new];
			del.found = [NSMutableDictionary dictionary];
			del.central = [[c alloc] initWithDelegate:del queue:dispatch_get_main_queue()
							  options:@{ @"kCBInitOptionShowPowerAlert" : @NO }];
		} else
			printf("LE: no CBCentralManager\n");
	}
	run_until(secs, classic && !le ? &scan_done : NULL);
	if (del)
		[del.central stopScan];
	printf("scan done: %lu classic, %lu LE\n", (unsigned long)seen.count, (unsigned long)del.found.count);
	return 0;
}

static int cmd_paired(void)
{
	size_t n = 0;
	BTHandle devs[256];
	char d[512];
	int r = BTLocalDeviceGetPairedDevices(local, devs, &n, 256);
	if (r) {
		fprintf(stderr, "btctl: BTLocalDeviceGetPairedDevices -> %d\n", r);
		return 1;
	}
	printf("%zu paired\n", n);
	for (size_t i = 0; i < n; i++) {
		describe(devs[i], d, sizeof(d));
		printf("  %s\n", d);
	}
	return 0;
}

static int cmd_pair(const char *addr, double secs)
{
	double end = now() + secs;
	int r;
	if (ensure_power() || lookup(addr, &target))
		return 1;
	BTServiceAddCallbacks(session, service_event, NULL);
	if (start_pairing_agent())
		return 1;
	seen = [NSMutableArray array];
	if (!start_scan()) {	/* bluetoothd learns the device (name, class) from inquiry, as Settings does */
		stamp();
		printf("scanning for %s (up to 15 s)\n", addr);
		run_until(15, &scan_done);
		BTDiscoveryAgentStopScan(discovery);
		stamp();
		printf("%s, stopping scan\n", scan_done ? "found" : "not seen in inquiry, connecting anyway");
	}
	r = BTDeviceConnectServices(target, ALL_SERVICES);
	stamp();
	printf("connect services 0x%x -> %d (pairing starts here if not paired)\n", ALL_SERVICES, r);
	if (r)
		return 1;
	run_until(end - now(), &pair_done);
	if (!pair_done) {
		int p = 0;
		BTDeviceGetPairingStatus(target, &p);
		printf("no pairing-complete event (pairing status %d)%s\n", p, p ? ": already paired?" : "");
	}
	if (!connect_done)
		run_until(end - now() > 5 ? end - now() : 5, &connect_done);
	run_until(3, NULL);	/* the remaining service events */
	char d[512];
	describe(target, d, sizeof(d));
	printf("result: pairing %s, %s\n", pair_done ? (pair_result ? "FAILED" : "ok") : "no event", d);
	return pair_done && pair_result ? 1 : 0;
}

static int cmd_connect(const char *addr, uint32_t mask)
{
	int r;
	if (ensure_power() || lookup(addr, &target))
		return 1;
	BTServiceAddCallbacks(session, service_event, NULL);
	start_pairing_agent();	/* in case the link asks for (re)pairing */
	r = BTDeviceConnectServices(target, mask);
	stamp();
	printf("connect services 0x%x -> %d\n", mask, r);
	if (!r)
		run_until(30, &connect_done);
	run_until(3, NULL);
	char d[512];
	describe(target, d, sizeof(d));
	printf("result: %s\n", d);
	return r != 0;
}

static int cmd_disconnect(const char *addr)
{
	int r;
	if (lookup(addr, &target))
		return 1;
	BTServiceAddCallbacks(session, service_event, NULL);
	r = BTDeviceDisconnect(target);
	stamp();
	printf("disconnect -> %d\n", r);
	if (!r)
		run_until(10, &connect_done);
	return r != 0;
}

static int cmd_unpair(const char *addr)
{
	int r;
	if (lookup(addr, &target))
		return 1;
	if ((r = BTPairingAgentCreate(session, &pcbs, NULL, &pairing)) == 0 &&
	    (r = BTPairingAgentDeletePairedDevice(pairing, target)) != 0 && BTPairingAgentStart(pairing) == 0)
		r = BTPairingAgentDeletePairedDevice(pairing, target);	/* retry with the agent started */
	printf("unpair %s -> %d\n", addr, r);
	run_until(1, NULL);
	return r != 0;
}

static int cmd_wait_pair(double secs)
{
	if (ensure_power())
		return 1;
	BTServiceAddCallbacks(session, service_event, NULL);
	if (start_pairing_agent())
		return 1;
	printf("set connectable -> %d, discoverable -> %d\n", BTLocalDeviceSetConnectable(local, -1),
	       BTLocalDeviceSetDiscoverable(local, -1));
	stamp();
	printf("waiting %.0f s for pairing requests (Ctrl-C ends)\n", secs);
	run_until(secs, NULL);
	BTLocalDeviceSetDiscoverable(local, 0);
	return 0;
}

static void usage(void)
{
	fprintf(stderr, "usage: btctl power on|off|status | discoverable on|off | scan [SECS] [-c|-l] | paired |\n"
			"       pair ADDR [SECS] | connect ADDR [MASK] | disconnect ADDR | unpair ADDR | wait-pair [SECS]\n");
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		setvbuf(stdout, NULL, _IOLBF, 0);
		t0 = now();
		if (argc < 2) {
			usage();
			return 2;
		}
		const char *cmd = argv[1], *a2 = argc > 2 ? argv[2] : NULL;
		if (load() || attach())
			return 1;
		int rc = 2;
		if (!strcmp(cmd, "power") && a2 && !strcmp(a2, "status"))
			rc = cmd_status();
		else if (!strcmp(cmd, "power") && a2 && (!strcmp(a2, "on") || !strcmp(a2, "off")))
			rc = power(!strcmp(a2, "on"));
		else if (!strcmp(cmd, "discoverable") && a2 && (!strcmp(a2, "on") || !strcmp(a2, "off")))
			rc = cmd_discoverable(!strcmp(a2, "on"));
		else if (!strcmp(cmd, "scan")) {
			double secs = 15;
			int classic = 1, le = getenv("BTCTL_NOLE") == NULL;
			for (int i = 2; i < argc; i++) {
				if (!strcmp(argv[i], "-c"))
					le = 0;
				else if (!strcmp(argv[i], "-l"))
					classic = 0;
				else
					secs = atof(argv[i]);
			}
			rc = cmd_scan(secs, classic, le);
		} else if (!strcmp(cmd, "paired"))
			rc = cmd_paired();
		else if (!strcmp(cmd, "pair") && a2)
			rc = cmd_pair(a2, argc > 3 ? atof(argv[3]) : 60);
		else if (!strcmp(cmd, "connect") && a2)
			rc = cmd_connect(a2, argc > 3 ? (uint32_t)strtoul(argv[3], NULL, 0) : ALL_SERVICES);
		else if (!strcmp(cmd, "disconnect") && a2)
			rc = cmd_disconnect(a2);
		else if (!strcmp(cmd, "unpair") && a2)
			rc = cmd_unpair(a2);
		else if (!strcmp(cmd, "wait-pair"))
			rc = cmd_wait_pair(a2 ? atof(a2) : 120);
		else
			usage();
		detach();
		return rc;
	}
}
