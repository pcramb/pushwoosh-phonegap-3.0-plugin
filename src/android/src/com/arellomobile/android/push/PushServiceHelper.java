package com.arellomobile.android.push;

import java.util.Set;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;

import com.arellomobile.android.push.utils.GeneralUtils;
import com.arellomobile.android.push.utils.PreferenceUtils;
import com.arellomobile.android.push.utils.notification.BannerNotificationFactory;
import com.arellomobile.android.push.utils.notification.BaseNotificationFactory;
import com.arellomobile.android.push.utils.notification.SimpleNotificationFactory;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import static com.google.android.gcm.GCMConstants.DEFAULT_INTENT_SERVICE_CLASS_NAME;

public class PushServiceHelper
{
	public static void generateNotification(Context context, Intent intent)
	{
		Bundle extras = intent.getExtras();
		if (extras == null)
		{
			return;
		}

		extras.putBoolean("foreground", GeneralUtils.isAppOnForeground(context));
		extras.putBoolean("onStart", !GeneralUtils.isAppOnForeground(context));

		String message = (String) extras.get("title");
		String header = (String) extras.get("header");

		// empty message with no data
		Intent notifyIntent = new Intent(context, PushHandlerActivity.class);
		notifyIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);

		// pass all bundle
		notifyIntent.putExtra("pushBundle", extras);

		if (header == null)
		{
			CharSequence appName = context.getPackageManager().getApplicationLabel(context.getApplicationInfo());
			if (null == appName)
			{
				appName = "";
			}

			header = appName.toString();
		}

		NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);

		BaseNotificationFactory notificationFactory;

		//is this banner notification?
		String bannerUrl = (String) extras.get("b");

		if (bannerUrl != null)
		{
			notificationFactory = new BannerNotificationFactory(context, extras, header, message, PreferenceUtils.getSoundType(context), PreferenceUtils.getVibrateType(context));
		}
		else
		{
			notificationFactory = new SimpleNotificationFactory(context, extras, header, message, PreferenceUtils.getSoundType(context), PreferenceUtils.getVibrateType(context));
		}
		notificationFactory.generateNotification();
		notificationFactory.addSoundAndVibrate();
		notificationFactory.addCancel();

		if (PreferenceUtils.getEnableLED(context))
		{
			notificationFactory.addLED(true);
		}

		Notification notification = notificationFactory.getNotification();

		int messageId = PreferenceUtils.getMessageId(context);
		if (PreferenceUtils.getMultiMode(context) == true)
		{
			PreferenceUtils.setMessageId(context, ++messageId);
		}

		notification.contentIntent = PendingIntent.getActivity(context, messageId, notifyIntent, PendingIntent.FLAG_CANCEL_CURRENT);

		if (!extras.getBoolean("silent", false))
		{
			manager.notify(messageId, notification);
		}

		generateBroadcast(context, extras);

		if (extras.getBoolean("local", false))
		{
			return;
		}

		try
		{
			DeviceFeature2_5.sendMessageDeliveryEvent(context, extras.getString("p"));
		}
		catch (Exception e)
		{
		}
	}

	public static void generateBroadcast(Context context, Bundle extras)
	{
		Intent broadcastIntent = new Intent();
		broadcastIntent.setAction(context.getPackageName() + ".action.PUSH_MESSAGE_RECEIVE");
		broadcastIntent.putExtras(extras);

		JSONObject dataObject = PushManager.bundleToJSON(extras);
		broadcastIntent.putExtra(BasePushMessageReceiver.JSON_DATA_KEY, dataObject.toString());

		if (GeneralUtils.isAmazonDevice())
		{
			context.sendBroadcast(broadcastIntent, context.getPackageName() + ".permission.RECEIVE_ADM_MESSAGE");
		}
		else
		{
			context.sendBroadcast(broadcastIntent, context.getPackageName() + ".permission.C2D_MESSAGE");
		}
	}

	/**
	 * Gets the class name of the intent service that will handle GCM messages.
	 */
	public static String getPushServiceClassName(Context context)
	{
		ApplicationInfo applicationInfo;
		try
		{
			//noinspection ConstantConditions
			applicationInfo = context.getPackageManager().getApplicationInfo(context.getApplicationContext().getPackageName(), PackageManager.GET_META_DATA);
			Bundle metaData = applicationInfo.metaData;
			if (metaData != null)
			{
				String pushService = applicationInfo.metaData.getString("PW_PUSH_SERVICE");

				if (pushService != null)
				{
					return pushService;
				}
			}
		}
		catch (Exception e)
		{
			// pass
		}

		return DEFAULT_INTENT_SERVICE_CLASS_NAME;
	}
}
