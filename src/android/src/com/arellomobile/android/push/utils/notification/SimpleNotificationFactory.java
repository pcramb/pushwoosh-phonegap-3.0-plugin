package com.arellomobile.android.push.utils.notification;

import android.app.Notification;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.text.Html;
import android.text.TextUtils;

import com.arellomobile.android.push.preference.SoundType;
import com.arellomobile.android.push.preference.VibrateType;
import com.pushwoosh.support.v4.app.NotificationCompat;

public class SimpleNotificationFactory extends BaseNotificationFactory
{
	public SimpleNotificationFactory(Context context, Bundle data, String header, String message, SoundType soundType, VibrateType vibrateType)
	{
		super(context, data, header, message, soundType, vibrateType);
	}

	@Override
	Notification generateNotificationInner(Context context, Bundle data, String header, String message, String tickerTitle)
	{
		int simpleIcon = Helper.tryToGetIconFormStringOrGetFromApplication(data.getString("i"), context);

		Bitmap customIconBitmap = null;
		String customIcon = data.getString("ci");
		if (customIcon != null)
		{
			float largeIconSize = context.getResources().getDimension(android.R.dimen.notification_large_icon_height);
			customIconBitmap = Helper.tryToGetBitmapFromInternet(customIcon, context, (int)largeIconSize);
		}

		NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(context);
		notificationBuilder.setContentTitle(getContent(header));
		notificationBuilder.setContentText(getContent(message));
		notificationBuilder.setSmallIcon(simpleIcon);
		notificationBuilder.setTicker(getContent(tickerTitle));
		notificationBuilder.setWhen(System.currentTimeMillis());

		notificationBuilder.setStyle(new NotificationCompat.BigTextStyle().bigText(getContent(message)));

		if (null != customIconBitmap)
		{
			notificationBuilder.setLargeIcon(customIconBitmap);
		}

		return notificationBuilder.build();
	}

	private CharSequence getContent(String content)
	{
		return TextUtils.isEmpty(content) ? content : Html.fromHtml(content);
	}
}
