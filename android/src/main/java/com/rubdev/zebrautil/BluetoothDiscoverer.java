
package com.rubdev.zebrautil;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothClass;
import android.bluetooth.BluetoothDevice;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import com.zebra.sdk.printer.discovery.DeviceFilter;
import com.zebra.sdk.printer.discovery.DiscoveredPrinterBluetooth;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class BluetoothDiscoverer {
    private final Context mContext;
    private final DiscoveryHandlerCustom mDiscoveryHandler;
    BluetoothDiscoverer.BtReceiver btReceiver;
    BluetoothDiscoverer.BtRadioMonitor btMonitor;
    private final DeviceFilter deviceFilter;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private volatile boolean isActive = false;
    private static BluetoothDiscoverer bluetoothDiscoverer;

    private BluetoothDiscoverer(Context context, DiscoveryHandlerCustom handler, DeviceFilter filter) {
        this.mContext = context.getApplicationContext();
        this.deviceFilter = filter;
        this.mDiscoveryHandler = handler;
    }

    public static void findPrinters(Context context, DiscoveryHandlerCustom handler, DeviceFilter filter) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            handler.discoveryError("No bluetooth radio found");
        } else if (!adapter.isEnabled()) {
            handler.discoveryError("Bluetooth radio is currently disabled");
        } else {
            if (adapter.isDiscovering()) {
                adapter.cancelDiscovery();
            }

            if (bluetoothDiscoverer == null) {
                bluetoothDiscoverer = new BluetoothDiscoverer(context.getApplicationContext(), handler, filter);
            }
            bluetoothDiscoverer.isActive = true;
            bluetoothDiscoverer.doBluetoothDisco();
        }

    }

    public static void findPrinters(Context context, DiscoveryHandlerCustom handler)  {
        DeviceFilter filter = value -> true;
        findPrinters(context, handler, filter);
    }

    private void unregisterTopLevelReceivers(Context context) {
        if (this.btReceiver != null) {
            try {
                context.unregisterReceiver(this.btReceiver);
            } catch (IllegalArgumentException ignored) {
                // Receiver was never registered, or already unregistered.
            }
            this.btReceiver = null;
        }

        if (this.btMonitor != null) {
            try {
                context.unregisterReceiver(this.btMonitor);
            } catch (IllegalArgumentException ignored) {
                // Receiver was never registered, or already unregistered.
            }
            this.btMonitor = null;
        }
    }

    public static void stopBluetoothDiscovery() {
        if (bluetoothDiscoverer != null) {
            bluetoothDiscoverer.isActive = false;
            bluetoothDiscoverer.handler.removeCallbacksAndMessages(null);
            BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
            if (adapter != null && adapter.isDiscovering()) {
                adapter.cancelDiscovery();
            }
            bluetoothDiscoverer.unregisterTopLevelReceivers(bluetoothDiscoverer.mContext);
            bluetoothDiscoverer = null;
        }
    }

    private void doBluetoothDisco() {
        this.btReceiver = new BluetoothDiscoverer.BtReceiver();
        this.btMonitor = new BluetoothDiscoverer.BtRadioMonitor();
        IntentFilter foundFilter = new IntentFilter(BluetoothDevice.ACTION_FOUND);
        IntentFilter finishedFilter = new IntentFilter(BluetoothAdapter.ACTION_DISCOVERY_FINISHED);
        IntentFilter stateFilter = new IntentFilter(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED);
        this.mContext.registerReceiver(this.btReceiver, foundFilter);
        this.mContext.registerReceiver(this.btReceiver, finishedFilter);
        this.mContext.registerReceiver(this.btMonitor, stateFilter);
        BluetoothAdapter.getDefaultAdapter().startDiscovery();

    }

    private class BtRadioMonitor extends BroadcastReceiver {
        private BtRadioMonitor() {
        }

        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED.equals(action)) {
                Bundle extras = intent.getExtras();
                if (extras == null) {
                    return;
                }
                int state = extras.getInt(BluetoothAdapter.EXTRA_STATE);
                if (state == 10) {
                    BluetoothDiscoverer.this.mDiscoveryHandler.discoveryFinished();
                }
            }

        }
    }

    private class BtReceiver extends BroadcastReceiver {
        private static final int BLUETOOTH_PRINTER_CLASS = 1664;
        private static final long DISCOVERY_INTERVAL = 10000;
        private static final long DEVICE_TIMEOUT = 28000;
        private final Map<BluetoothDevice,Long> foundDevices;

        private BtReceiver() {
            this.foundDevices = new HashMap<>();
        }

        public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            if (BluetoothDevice.ACTION_FOUND.equals(action)) {
                this.processFoundPrinter(intent);
            } else if (BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(action)) {
                checkForMissingDevices();
                BluetoothDiscoverer.this.mDiscoveryHandler.discoveryFinished();
                BluetoothDiscoverer.this.handler.postDelayed(() -> {
                    if (!BluetoothDiscoverer.this.isActive) {
                        return;
                    }
                    BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
                    if (adapter != null && adapter.isEnabled()) {
                        adapter.startDiscovery();
                    }
                }, DISCOVERY_INTERVAL);
            }

        }

        private void checkForMissingDevices() {
            long currentTime = System.currentTimeMillis();
            Iterator<Map.Entry<BluetoothDevice, Long>> iterator = foundDevices.entrySet().iterator();
            while (iterator.hasNext()) {
                Map.Entry<BluetoothDevice,Long> entry = iterator.next();
                long lastSeenTime = entry.getValue();
                BluetoothDevice lastSeenDevice = entry.getKey();
               if (currentTime - lastSeenTime > DEVICE_TIMEOUT) {
                   mDiscoveryHandler.printerOutOfRange(
                            new DiscoveredPrinterBluetooth(
                                    lastSeenDevice.getAddress(),
                                    lastSeenDevice.getName()));
                    iterator.remove();
                }
            }
        }

        private void processFoundPrinter(Intent intent) {
            BluetoothDevice device = (BluetoothDevice) intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
            if (device == null) {
                return;
            }
            if (this.isPrinterClass(device) && BluetoothDiscoverer.this.deviceFilter != null && BluetoothDiscoverer.this.deviceFilter.shouldAddPrinter(device)) {

                if (!this.foundDevices.containsKey(device)) {
                    BluetoothDiscoverer.this.mDiscoveryHandler.foundPrinter(new DiscoveredPrinterBluetooth(device.getAddress(), device.getName()));
                }
                Long foundAt = System.currentTimeMillis();
                this.foundDevices.put(device, foundAt);
            }

        }

        private boolean isPrinterClass(BluetoothDevice device) {
            BluetoothClass btClass = device.getBluetoothClass();
            if (btClass != null) {
                return btClass.getDeviceClass() == BLUETOOTH_PRINTER_CLASS;
            } else {
                return false;
            }
        }
    }
}
