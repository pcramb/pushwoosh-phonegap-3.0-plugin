//
//  MessageActivity.java
//
// Pushwoosh Push Notifications SDK
// www.pushwoosh.com
//
// MIT Licensed

package com.arellomobile.android.push.utils;

import android.content.Context;
import android.content.SharedPreferences;

import com.arellomobile.android.push.preference.SoundType;
import com.arellomobile.android.push.preference.VibrateType;

public class PreferenceUtils
{
	private static final String PREFERENCE = "com.pushwoosh.pushnotifications";

	private static final String LAST_REGISTRATION = "last_registration_change";

	public static String getProjectId(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		return prefs.getString("dm_sender_id", "");
	}

	public static void setProjectId(Context context, String projectId)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		final SharedPreferences.Editor editor = prefs.edit();
		editor.putString("dm_sender_id", projectId);
		editor.commit();
	}

	public static long getLastRegistration(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		return prefs.getLong(LAST_REGISTRATION, 0);
	}

	public static void setLastRegistration(Context context, long lastRegistrationTime)
	{
		final SharedPreferences.Editor editor = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE).edit();
		editor.putLong(LAST_REGISTRATION, lastRegistrationTime);
		editor.commit();
	}

	public static void resetLastRegistration(Context context)
	{
		final SharedPreferences.Editor editor = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE).edit();
		editor.remove(LAST_REGISTRATION);
		editor.commit();
	}

	public static void setApplicationId(Context context, String applicationId)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putString("dm_pwapp", applicationId);
		editor.commit();
	}

	public static String getApplicationId(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		String applicationId = prefs.getString("dm_pwapp", "");
		return applicationId;
	}
	
	public static void setForceRegister(Context context, boolean forceRegister)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putBoolean("pw_forceregister", forceRegister);
		editor.commit();
	}

	public static boolean getForceRegister(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		boolean multiOn = prefs.getBoolean("pw_forceregister", false);
		return multiOn;
	}
	
	public static void setMultiMode(Context context, boolean multiOn)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putBoolean("dm_multimode", multiOn);
		editor.commit();
	}

	public static boolean getMultiMode(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		boolean multiOn = prefs.getBoolean("dm_multimode", false);
		return multiOn;
	}
	
	public static void setSoundType(Context context, SoundType type)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putInt("dm_soundtype", type.getValue());
		editor.commit();
	}

	public static SoundType getSoundType(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		Integer type = prefs.getInt("dm_soundtype", 0);
		
		return SoundType.fromInt(type);
	}
	
	public static void setVibrateType(Context context, VibrateType type)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putInt("dm_vibratetype", type.getValue());
		editor.commit();
	}

	public static VibrateType getVibrateType(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		Integer type = prefs.getInt("dm_vibratetype", 0);
		
		return VibrateType.fromInt(type);
	}
	
	public static void setMessageId(Context context, int messageId)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putInt("dm_messageid", messageId);
		editor.commit();
	}

	public static int getMessageId(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		int value = prefs.getInt("dm_messageid", 1001);
		
		return value;
	}
	
	public static void setLightScreenOnNotification(Context context, boolean lightsOn)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putBoolean("dm_lightson", lightsOn);
		editor.commit();
	}

	public static boolean getLightScreenOnNotification(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		boolean lightsOn = prefs.getBoolean("dm_lightson", false);
		return lightsOn;
	}
	
	public static void setEnableLED(Context context, boolean ledOn)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		SharedPreferences.Editor editor = prefs.edit();
		editor.putBoolean("dm_ledon", ledOn);
		editor.commit();
	}

	public static boolean getEnableLED(Context context) {
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		boolean ledOn = prefs.getBoolean("dm_ledon", false);
		return ledOn;
	}
	
	public static String getBaseUrl(Context context)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		return prefs.getString("pw_base_url", "");
	}

	public static void setBaseUrl(Context context, String baseUrl)
	{
		final SharedPreferences prefs = context.getSharedPreferences(PREFERENCE, Context.MODE_PRIVATE);
		final SharedPreferences.Editor editor = prefs.edit();
		editor.putString("pw_base_url", baseUrl);
		editor.commit();
	}

}
