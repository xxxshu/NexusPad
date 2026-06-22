package com.nexuspad.nexuspad_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.FileOutputStream

/**
 * USB AOA (Android Open Accessory) 通信插件
 *
 * MethodChannel: com.nexuspad.usb
 *   - getAccessory: 检查已连接的 AOA 设备
 *   - requestPermission: 请求 USB Accessory 权限
 *   - openAccessory: 打开 Accessory 并建立读写流
 *   - writeData: 发送 TLV 帧数据
 *   - close: 关闭连接
 *
 * EventChannel: com.nexuspad.usb/stream
 *   - 接收 TLV 帧数据 (from Bulk In)
 */
class UsbHostPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var usbManager: UsbManager? = null
    private var accessoryFd: ParcelFileDescriptor? = null
    private var inputStream: FileInputStream? = null
    private var outputStream: FileOutputStream? = null
    private var readThread: Thread? = null
    private var eventSink: EventChannel.EventSink? = null

    private val ACTION_USB_PERMISSION = "com.nexuspad.nexuspad_app.USB_PERMISSION"

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (ACTION_USB_PERMISSION == intent.action) {
                synchronized(this) {
                    val accessory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY, UsbAccessory::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY)
                    }
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted && accessory != null) {
                        openAccessoryInternal(accessory)
                    } else {
                        // Permission denied — notify via method channel if pending
                    }
                }
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

        methodChannel = MethodChannel(binding.binaryMessenger, "com.nexuspad.usb")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "com.nexuspad.usb/stream")
        eventChannel.setStreamHandler(this)

        // Register permission receiver
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(permissionReceiver, filter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        closeConnection()
        try {
            context.unregisterReceiver(permissionReceiver)
        } catch (_: Exception) {}
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAccessory" -> {
                val accessory = findAccessory()
                if (accessory != null) {
                    result.success(mapOf(
                        "manufacturer" to accessory.manufacturer,
                        "model" to accessory.model,
                        "version" to accessory.version,
                        "description" to accessory.description,
                        "uri" to accessory.uri,
                        "serial" to accessory.serial,
                    ))
                } else {
                    result.success(null)
                }
            }

            "requestPermission" -> {
                val accessory = findAccessory()
                if (accessory == null) {
                    result.error("NO_DEVICE", "No AOA accessory found", null)
                    return
                }
                if (usbManager?.hasPermission(accessory) == true) {
                    result.success(true)
                } else {
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_MUTABLE
                    } else {
                        0
                    }
                    val permissionIntent = PendingIntent.getBroadcast(
                        context, 0, Intent(ACTION_USB_PERMISSION), flags
                    )
                    usbManager?.requestPermission(accessory, permissionIntent)
                    result.success(true)
                }
            }

            "openAccessory" -> {
                val accessory = findAccessory()
                if (accessory == null) {
                    result.error("NO_DEVICE", "No AOA accessory found", null)
                    return
                }
                if (usbManager?.hasPermission(accessory) != true) {
                    result.error("NO_PERMISSION", "USB permission not granted", null)
                    return
                }
                openAccessoryInternal(accessory)
                result.success(accessoryFd != null)
            }

            "writeData" -> {
                val data = call.arguments as? ByteArray
                if (data == null) {
                    result.error("INVALID_DATA", "Expected byte array", null)
                    return
                }
                try {
                    outputStream?.write(data)
                    outputStream?.flush()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("WRITE_ERROR", e.message, null)
                }
            }

            "isConnected" -> {
                result.success(inputStream != null && outputStream != null)
            }

            "close" -> {
                closeConnection()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun findAccessory(): UsbAccessory? {
        val accessories = usbManager?.accessoryList
        return accessories?.firstOrNull()
    }

    private fun openAccessoryInternal(accessory: UsbAccessory) {
        closeConnection()

        try {
            val fd = usbManager?.openAccessory(accessory) ?: return
            accessoryFd = fd
            inputStream = FileInputStream(fd.fileDescriptor)
            outputStream = FileOutputStream(fd.fileDescriptor)

            // Start read thread
            readThread = Thread {
                val buffer = ByteArray(4096)
                try {
                    while (!Thread.currentThread().isInterrupted) {
                        val len = inputStream?.read(buffer) ?: break
                        if (len <= 0) break
                        val data = buffer.copyOf(len)
                        // Post to main thread for EventChannel
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            eventSink?.success(data)
                        }
                    }
                } catch (e: Exception) {
                    if (!Thread.currentThread().isInterrupted) {
                        android.os.Handler(android.os.Looper.getMainLooper()).post {
                            eventSink?.error("READ_ERROR", e.message, null)
                        }
                    }
                } finally {
                    closeConnection()
                }
            }
            readThread?.start()
        } catch (e: Exception) {
            closeConnection()
        }
    }

    private fun closeConnection() {
        readThread?.interrupt()
        readThread = null
        try { inputStream?.close() } catch (_: Exception) {}
        try { outputStream?.close() } catch (_: Exception) {}
        try { accessoryFd?.close() } catch (_: Exception) {}
        inputStream = null
        outputStream = null
        accessoryFd = null
    }
}
