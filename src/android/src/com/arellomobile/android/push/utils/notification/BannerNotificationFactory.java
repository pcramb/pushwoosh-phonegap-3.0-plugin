package com.arellomobile.android.push.utils.notification;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.text.Html;
import android.text.TextUtils;

import com.arellomobile.android.push.preference.SoundType;
import com.arellomobile.android.push.preference.VibrateType;
import com.pushwoosh.support.v4.app.NotificationCompat;

/**
 * Date: 30.10.12
 * Time: 18:08
 *
 * @author MiG35
 */
public class BannerNotificationFactory extends BaseNotificationFactory
{
	public BannerNotificationFactory(Context context, Bundle data, String header, String message, SoundType soundType, VibrateType vibrateType)
	{
		super(context, data, header, message, soundType, vibrateType);
	}

	@SuppressLint("NewApi")
	@Override
	Notification generateNotificationInner(Context context, Bundle data, String header, String message, String tickerTitle)
	{
		String link = getData().getString("b");
		Bitmap bitmap = Helper.tryToGetBitmapFromInternet(link, getContext(), -1);

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
		notificationBuilder.setSubText(getContent(message));
		notificationBuilder.setSmallIcon(simpleIcon);
		notificationBuilder.setTicker(getContent(tickerTitle));
		notificationBuilder.setWhen(System.currentTimeMillis());

		if (bitmap != null)
		{
			//It should be image with 450dp width and 2:1 aspect ration (see slide 52)
			notificationBuilder.setStyle(new NotificationCompat.BigPictureStyle().bigPicture(bitmap));
		}
		if (customIconBitmap != null)
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
