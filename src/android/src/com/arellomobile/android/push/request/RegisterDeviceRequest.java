package com.arellomobile.android.push.request;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Locale;
import java.util.Map;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;

import com.arellomobile.android.push.utils.GeneralUtils;

public class RegisterDeviceRequest extends PushRequest
{
	private static final String GOOGLE = "3";
	private static final String AMAZON = "9";

	private String pushToken;

	public RegisterDeviceRequest(String pushToken)
	{
		this.pushToken = pushToken;
	}

	@Override
	public String getMethod()
	{
		return "registerDevice";
	}

	@Override
	protected void buildParams(Context context, Map<String, Object> params)
	{
		params.put("device_name", GeneralUtils.isTablet(context) ? "Tablet" : "Phone");

		//check for Amazon (Kindle) or Google device
		if (GeneralUtils.isAmazonDevice())
		{
			params.put("device_type", AMAZON);
		}
		else
		{
			params.put("device_type", GOOGLE);
		}

		params.put("v", "2.2");
		params.put("language", Locale.getDefault().getLanguage());
		params.put("timezone", Calendar.getInstance().getTimeZone().getRawOffset() / 1000); // converting from milliseconds to seconds

		String packageName = context.getPackageName();
		params.put("android_package", packageName);
		params.put("push_token", pushToken);

		ArrayList<String> rawResourses = GeneralUtils.getRawResourses(context);
		params.put("sounds", rawResourses);
		
		String name = context.getPackageManager().getInstallerPackageName(packageName);
		if(name == null)
			params.put("jailbroken", 1);
		else
			params.put("jailbroken", 0);
		
		params.put("device_model", getDeviceName());
		
		String androidVersion = android.os.Build.VERSION.RELEASE;
		params.put("os_version", androidVersion);

		try
		{
			//noinspection ConstantConditions
			params.put("app_version", context.getPackageManager().getPackageInfo(packageName, 0).versionName);
		}
		catch (PackageManager.NameNotFoundException e)
		{
			// pass
		}
	}
	
	public String getDeviceName() {
		String manufacturer = Build.MANUFACTURER;
		String model = Build.MODEL;
		if (model.startsWith(manufacturer)) {
			return capitalize(model);
		} else {
			return capitalize(manufacturer) + " " + model;
		}
	}

	private String capitalize(String s) {
		if (s == null || s.length() == 0) {
			return "";
		}
		char first = s.charAt(0);
		if (Character.isUpperCase(first)) {
			return s;
		} else {
			return Character.toUpperCase(first) + s.substring(1);
		}
	}
}
