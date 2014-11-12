//
//  PushManager.java
//
// Pushwoosh Push Notifications SDK
// www.pushwoosh.com
//
// MIT Licensed

package com.arellomobile.android.push;

import java.math.BigDecimal;
import java.util.Calendar;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.location.Location;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.Bundle;
import android.os.Handler;
import android.text.TextUtils;

import com.arellomobile.android.push.preference.SoundType;
import com.arellomobile.android.push.preference.VibrateType;
import com.arellomobile.android.push.registrar.PushRegistrar;
import com.arellomobile.android.push.registrar.PushRegistrarGCM;
import com.arellomobile.android.push.utils.executor.ExecutorHelper;
import com.arellomobile.android.push.utils.GeneralUtils;
import com.arellomobile.android.push.utils.PreferenceUtils;
import com.arellomobile.android.push.utils.WorkerTask;
import com.google.android.gcm.GCMRegistrar;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Push notifications manager
 */
public class PushManager
{
	private static final String HTML_URL_FORMAT = "https://cp.pushwoosh.com/content/%s";

	public static final String REGISTER_EVENT = "REGISTER_EVENT";
	public static final String REGISTER_ERROR_EVENT = "REGISTER_ERROR_EVENT";
	public static final String UNREGISTER_EVENT = "UNREGISTER_EVENT";
	public static final String UNREGISTER_ERROR_EVENT = "UNREGISTER_ERROR_EVENT";
	public static final String PUSH_RECEIVE_EVENT = "PUSH_RECEIVE_EVENT";

	public static final String REGISTER_BROAD_CAST_ACTION = "com.arellomobile.android.push.REGISTER_BROAD_CAST_ACTION";

	private Context mContext;
	
	private PushRegistrar pushRegistrar;
	
	private static PushManager instance = null;

	/**
	 * Get context
	 * @return PushManager context
	 */
	Context getContext() {
		return mContext;
	}

	private static final Object mSyncObj = new Object();
	private static AsyncTask<Void, Void, Void> mRegistrationAsyncTask;

	/**
	 * Initializes push manager. Private.
	 * @param context
	 */
	private PushManager(Context context)
	{
		GeneralUtils.checkNotNull(context, "context");
		mContext = context;
		
		if(GeneralUtils.isAmazonDevice())
		{
			System.out.println("Pushwoosh: Phonegap Build Plugin is not supported on Amazon Device");
			pushRegistrar = new PushRegistrarGCM(context);
		}
		else
		{
			pushRegistrar = new PushRegistrarGCM(context);
		}
	}

	/**
	 * Init push manager with Pushwoosh App ID and Project ID for GCM.
	 * Use either this function or place the values in AndroidManifest.xml as per documentation.
	 *
	 * @param context
	 * @param appId Pushwoosh Application ID
	 * @param projectId ProjectID from Google GCM
	 */
	static public void initializePushManager(Context context, String appId, String projectId)
	{
		PreferenceUtils.setApplicationId(context, appId);
		PreferenceUtils.setProjectId(context, projectId);
	}

	/**
	 * Returns current instance of PushManager. Can return null if Project ID or Pushwoosh App Id not given.
	 *
	 * @param context
	 */
	static public PushManager getInstance(Context context)
	{
		if(instance == null)
		{
			String appId = null;
			String projectId = null;
			
			//try to get Pushwoosh App ID and Project ID from AndroidManifest.xml 
			try
			{
				ApplicationInfo ai = context.getPackageManager().getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
				appId = ai.metaData.getString("PW_APPID");

				try
				{
					projectId = ai.metaData.getString("PW_PROJECT_ID").substring(1);
				}
				catch(Exception e)
				{}
			} catch (Exception e)
			{}
			
			if(TextUtils.isEmpty(appId))
				appId = PreferenceUtils.getApplicationId(context);
			
			if(TextUtils.isEmpty(projectId))
				projectId = PreferenceUtils.getProjectId(context);
			
			//no project id needed for Amazon
			if(GeneralUtils.isAmazonDevice())
			{
				projectId = "AMAZON_DEVICE";
			}
			
			if(TextUtils.isEmpty(appId) || TextUtils.isEmpty(projectId))
			{
				System.out.println("Tried to get instance of PushManager with no Pushwoosh App ID or Project Id set");
				return null;
			}
				
			System.out.println("App ID: " + appId);
			System.out.println("Project ID: " + projectId);

			//check if App ID has been changed
			String oldAppId = PreferenceUtils.getApplicationId(context);
			if (!oldAppId.equals(appId))
			{
				PreferenceUtils.setForceRegister(context, true);
			}

			PreferenceUtils.setApplicationId(context, appId);
			PreferenceUtils.setProjectId(context, projectId);
			
			instance = new PushManager(context);
		}
		
		return instance;
	}
	
	/**
	 * Must be called after initialization on app start. Tracks app open for Pushwoosh stats. To register use {@link registerForPushNotifications}
	 *
	 * @param context current context
	 * @throws Exception - push notifications are not available on the device, or prerequisites are not met
	 */
	public void onStartup(Context context) throws Exception
	{
		//check for manifest and permissions
		pushRegistrar.checkDevice(context);

		//register app open
		sendAppOpen(context);

		if (context instanceof Activity)
		{
			if (((Activity) context).getIntent().hasExtra(PushManager.PUSH_RECEIVE_EVENT))
			{
				// if this method gets called because of push message, we don't need to register
				return;
			}
		}
		
		final String regId = GCMRegistrar.getRegistrationId(mContext);
		if (regId != null && !regId.equals(""))
		{
			//if we need to re-register on Pushwoosh because of Pushwoosh App Id change
			boolean forceRegister = PreferenceUtils.getForceRegister(context);
			PreferenceUtils.setForceRegister(context, false);
			if (forceRegister)
			{
				registerOnPushWoosh(context, regId);
			}
			else
			{
				if (neededToRequestPushWooshServer(context))
				{
					registerOnPushWoosh(context, regId);
				}
			}
		}
	}

	/**
	 * Starts tracking Geo Push Notifications
	 */
	public void startTrackingGeoPushes()
	{
		mContext.startService(new Intent(mContext, GeoLocationService.class));
	}

	static public void startTrackingGeoPushes(Context context)
	{
		context.startService(new Intent(context, GeoLocationService.class));
	}

	/**
	 * Stop tracking Geo Push Notifications
	 */
	public void stopTrackingGeoPushes()
	{
		mContext.stopService(new Intent(mContext, GeoLocationService.class));
	}

	static public void stopTrackingGeoPushes(Context context)
	{
		context.stopService(new Intent(context, GeoLocationService.class));
	}

	/**
	 * Starts tracking Beacon Push Notifications
	 */
	public void startTrackingBeaconPushes()
	{
		// start beacon service
		System.out.println("Pushwoosh: Beacons are not suppported on Phonegap Build Plugin ");
	}

	/**
	 * Stop tracking Beacon Push Notifications
	 */
	public void stopTrackingBeaconPushes()
	{
		System.out.println("Pushwoosh: Beacons are not suppported on Phonegap Build Plugin ");
	}

	/**
	 * Gets push notification token. May be null if not registered for push notifications yet.
	 */
	static public String getPushToken(Context context)
	{
		return GCMRegistrar.getRegistrationId(context);
	}

	/**
	 * Gets Pushwoosh HWID. Unique device identifier that is used in API communication with Pushwoosh. 
	 */
	static public String getPushwooshHWID(Context context)
	{
		return GeneralUtils.getDeviceUUID(context);
	}

	/**
	 * Registers for push notifications. 
	 */
	public void registerForPushNotifications()
	{
		final String regId = GCMRegistrar.getRegistrationId(mContext);
		//haven't been registered before, register then
		if (regId.equals(""))
		{
			try
			{
				pushRegistrar.registerPW(mContext);
			}
			catch(Exception e)
			{
				e.printStackTrace();
			}
		}
		else
		{
			PushEventsTransmitter.onRegistered(mContext, regId);
		}
	}

	/**
	 * Unregister from push notifications
	 */
	public void unregisterForPushNotifications()
	{
		cancelPrevRegisterTask();

		pushRegistrar.unregisterPW(mContext);
	}

	/**
	 * Get push notification user data
	 *
	 * @return string user data, or null
	 */
	public String getCustomData(Bundle pushBundle)
	{
		if (pushBundle == null)
		{
			return null;
		}

		return pushBundle.getString("u");
	}

	//	------------------- 2.5 Features STARTS -------------------

	/**
	 * Send tags synchronously.
	 * WARNING!
	 * Be sure to call this method from working thread.
	 * If not, you will freeze UI or runtime exception on Android >= 3.0
	 *
	 * @param tags tags to send. Value can be String or Integer only - if not Exception will be thrown
	 * @return wrong tags. key is name of the tag
	 * @throws PushWooshException
	 */
	public static Map<String, String> sendTagsFromBG(Context context, Map<String, Object> tags)
			throws Exception
	{
		Map<String, String> wrongTags = new HashMap<String, String>();
		DeviceFeature2_5.sendTags(context, tags);

		return wrongTags;
	}

	/**
	 * Send tags asynchronously from UI
	 *
	 * @param context
	 * @param tags tags to send. Value can be String or Integer only - if not Exception will be thrown
	 * @param callBack result callback
	 */
	public static void sendTagsFromUI(final Context context, final Map<String, Object> tags, final SendPushTagsCallBack listener)
	{
		sendTags(context, tags, listener);
	}

	/**
	 * Send tags asynchronously
	 *
	 * @param context
	 * @param tags tags to send. Value can be String or Integer only - if not Exception will be thrown
	 * @param callBack execute result callback
	 */
	public static void sendTags(final Context context, final Map<String, Object> tags, final SendPushTagsCallBack listener)
	{
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.sendTags(context, tags);
							if(listener != null)
								listener.onSentTagsSuccess(new HashMap<String, String>());
						} catch (Exception e) {
							if(listener != null)
								listener.onSentTagsError(e);
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	/**
	 * Get tags listener
	 */
	public interface GetTagsListener {
		/**
		 * Called when tags received
		 *
		 * @param tags received tags map
		 */
		public void onTagsReceived(Map<String, Object> tags);

		/**
		 * Called when request failed
		 *
		 * @param e Exception
		 */
		public void onError(Exception e);
	}

	/**
	 * Get tags from Pushwoosh service synchronously
	 *
	 * @param context
	 * @return tags, or null
	 */
	public static Map<String, Object> getTagsSync(final Context context)
	{
		if (GCMRegistrar.isRegisteredOnServer(context) == false)
			return null;
		
		try {
			return DeviceFeature2_5.getTags(context);
		} catch (Exception e) {
			return new HashMap<String, Object>();
		}
	}

	/**
	 * Get tags from Pushwoosh service asynchronously
	 *
	 * @param context
	 * @return tags, or null
	 */
	public static void getTagsAsync(final Context context, final GetTagsListener listener)
	{
		if (GCMRegistrar.isRegisteredOnServer(context) == false)
			return;
		
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						Map<String, Object> tags;
						try {
							tags = DeviceFeature2_5.getTags(context);
							if(listener != null)
								listener.onTagsReceived(tags);
						} catch (Exception e) {
							if(listener != null)
								listener.onError(e);
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});		
	}

	/**
	 * Send location to Pushwoosh service asynchronously
	 *
	 * @param context
	 * @param location
	 */
	public static void sendLocation(final Context context, final Location location)
	{
		if (GCMRegistrar.isRegisteredOnServer(context) == false)
			return;

		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.getNearestZone(context, location);
						} catch (Exception e) {
//								e.printStackTrace();
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	public static void getBeacons(final Context context, final GetBeaconsListener listener) {
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							JSONObject response = DeviceFeature2_5.getBeacons(context);
							if(listener != null)
								listener.onBeaconsReceived(response);
						} catch (Exception e) {
							if(listener != null)
								listener.onBeaconsError(e);
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	public interface GetBeaconsListener {
		/**
		 * Called when beacons received
		 *
		 * @param response received tags map
		 */
		public void onBeaconsReceived(JSONObject response);

		/**
		 * Called when request failed
		 *
		 * @param e Exception
		 */
		public void onBeaconsError(Exception e);
	}

	/**
	 * Internal function. Processes beacon in vicinity.
	 */
	public static void processBeacon(final Context context, final String proximityUuid, final String major, final String minor, final String action) {
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.processBeacon(context, proximityUuid, major, minor, action);
						} catch (Exception e) {
							e.printStackTrace();
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	//	------------------- 2.5 Features ENDS -------------------


	//	------------------- PREFERENCE STARTS -------------------

	/**
	 * Allows multiple notifications in notification bar.
	 *
	 * @param context
	 */
	public static void setMultiNotificationMode(Context context)
	{
		PreferenceUtils.setMultiMode(context, true);
	}

	/**
	 * Allows only the last notification in notification bar.
	 */
	public static void setSimpleNotificationMode(Context context)
	{
		PreferenceUtils.setMultiMode(context, false);
	}

	/**
	 * Change sound notification type
	 *
	 * @param context
	 * @param soundNotificationType target sound type
	 */
	public static void setSoundNotificationType(Context context, SoundType soundNotificationType)
	{
		PreferenceUtils.setSoundType(context, soundNotificationType);
	}

	/**
	 * Change vibration notification type
	 *
	 * @param context
	 * @param vibrateNotificationType target vibration type
	 */
	public static void setVibrateNotificationType(Context context, VibrateType vibrateNotificationType)
	{
		PreferenceUtils.setVibrateType(context, vibrateNotificationType);
	}

	/**
	 * Enable/disable screen light when notification message arrives
	 *
	 * @param context
	 * @param lightsOn
	 */
	public static void setLightScreenOnNotification(Context context, boolean lightsOn)
	{
		PreferenceUtils.setLightScreenOnNotification(context, lightsOn);
	}

	/**
	 * Enable/disable LED highlight when notification message arrives
	 *
	 * @param context
	 * @param ledOn
	 */
	public static void setEnableLED(Context context, boolean ledOn)
	{
		PreferenceUtils.setEnableLED(context, ledOn);
	}

	public static void setBeaconBackgroundMode(Context context, boolean backgroundMode) {
		System.out.println("Pushwoosh: Beacons are not suppported on Phonegap Build Plugin ");
	}
	
	//	------------------- PREFERENCE END -------------------

	/**
	 * Internal function
	 */
	public static JSONObject bundleToJSON(Bundle pushBundle)
	{
		JSONObject dataObject = new JSONObject();
		Set<String> keys = pushBundle.keySet();
		for (String key : keys)
		{
			//backward compatibility
			if(key.equals("u"))
			{
				try
				{
					Object userData = pushBundle.get("u");
					if (userData != null && userData instanceof String)
					{
						if (((String) userData).startsWith("{"))
						{
							userData = new JSONObject((String) userData);
						}
						else if (((String) userData).startsWith("["))
						{
							userData = new JSONArray((String) userData);
						}
						dataObject.put("userdata", userData);
					}
				}
				catch (JSONException e)
				{
					// pass
				}
			}
			
			try
			{
				dataObject.put(key, pushBundle.get(key));
			}
			catch (JSONException e)
			{
				// pass
			}
		}
		
		return dataObject;
	}
	
	//	------------------- HANDLING PUSH MESSAGE STARTS -------------------

	/**
	 * Called during push message processing, processes push notifications payload. Used internally!
	 *
	 * @param activity that handles push notification
	 * @return false if activity doesn't have pushBundle, true otherwise
	 */
	static boolean onHandlePush(Activity activity)
	{
		Intent intent = activity.getIntent();
		Bundle pushBundle = preHandlePush(activity, intent);
		if(pushBundle == null)
			return false;

		JSONObject dataObject = bundleToJSON(pushBundle);
		PushEventsTransmitter.onMessageReceive(activity, dataObject.toString(), pushBundle);

		postHandlePush(activity, intent);
		return true;
	}

	/**
	 * Internal function.
	 */
	public static Bundle preHandlePush(Context context, Intent pushIntent)
	{
		Bundle pushBundle = pushIntent.getBundleExtra("pushBundle");
		if (null == pushBundle)
		{
			return null;
		}

		// send pushwoosh callback
		sendPushStat(context, pushBundle.getString("p"));

		String link = pushBundle.getString("l");
		if (!TextUtils.isEmpty(link))
		{
			Intent notifyIntent = new Intent(Intent.ACTION_VIEW, Uri.parse(link));
			notifyIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			context.startActivity(notifyIntent);
			return null;
		}

		return pushBundle;
	}

	/**
	 * Internal function.
	 */
	public static boolean postHandlePush(Context context, Intent pushIntent)
	{
		Bundle pushBundle = pushIntent.getBundleExtra("pushBundle");
		if (null == pushBundle)
		{
			return false;
		}

		// push message handling
		String url = (String) pushBundle.get("h");

		if (url != null)
		{
			url = String.format(HTML_URL_FORMAT, url);

			// show browser
			Intent intent = new Intent(context, PushWebview.class);
			intent.putExtra("url", url);
			context.startActivity(intent);
		}
		
		String customPageUrl = (String) pushBundle.get("r");
		if(customPageUrl != null) {
			// show browser
			Intent intent = new Intent(context, PushWebview.class);
			intent.putExtra("url", customPageUrl);
			context.startActivity(intent);
		}
		
		//temporary disable this code until the server supports it
		String packageName = (String) pushBundle.get("launch");
		if(packageName != null)
		{
			Intent launchIntent = null;
			try
			{
				launchIntent = context.getPackageManager().getLaunchIntentForPackage(packageName);
			}
			catch(Exception e)
			{
			// if no application found
			}
			
			if(launchIntent != null)
			{
				context.startActivity(launchIntent);
			}
		}

		return true;
	}

	//	------------------- HANDLING PUSH MESSAGE END -------------------


	//	------------------- PRIVATE METHODS -------------------

	/**
	 * Check if we need to register on Pushwoosh. Private function.
	 *
	 * @param context
	 * @return true if registered in last 10 min, false otherwise
	 */
	private boolean neededToRequestPushWooshServer(Context context)
	{
		Calendar nowTime = Calendar.getInstance();
		Calendar tenMinutesBefore = Calendar.getInstance();
		tenMinutesBefore.add(Calendar.MINUTE, -10); // decrement 10 minutes

		Calendar lastPushWooshRegistrationTime = Calendar.getInstance();
		lastPushWooshRegistrationTime.setTime(new Date(PreferenceUtils.getLastRegistration(context)));

		if (tenMinutesBefore.before(lastPushWooshRegistrationTime) && lastPushWooshRegistrationTime.before(nowTime))
		{
			// tenMinutesBefore <= lastPushWooshRegistrationTime <= nowTime
			return false;
		}
		return true;
	}

	/**
	 * Registers on Pushwoosh service asynchronously, private function
	 *
	 * @param context
	 * @param regId registration ID
	 */
	private void registerOnPushWoosh(final Context context, final String regId)
	{
		cancelPrevRegisterTask();

		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				// if not register yet or an other id detected
				mRegistrationAsyncTask = getRegisterAsyncTask(context, regId);

				ExecutorHelper.executeAsyncTask(mRegistrationAsyncTask);
			}
		});
	}

	/**
	 * Sends push stat asynchronously, used internally
	 * @param context
	 * @param hash
	 */
	static void sendPushStat(final Context context, final String hash)
	{
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.sendPushStat(context, hash);
						} catch (Exception e) {
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	/**
	 * Sends service message that app has been opened
	 *
	 * @param context
	 */
	private void sendAppOpen(final Context context)
	{
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.sendAppOpen(context);
						} catch (Exception e) {
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	/**
	 * Sends goal achieved asynchronously
	 *
	 * @param context
	 * @param goal
	 * @param count
	 */
	public static void sendGoalAchieved(final Context context, final String goal, final Integer count)
	{
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.sendGoalAchieved(context, goal, count);
						} catch (Exception e) {
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	/**
	 * Track in-app purchase
	 *
	 * @param context
	 * @param sku purchased product ID
	 * @param price price for the product
	 * @param currency currency of the price (ex: "USD")
	 * @param purchaseTime time of the purchase (ex: new Date())
	 */
	public static void trackInAppRequest(final Context context, final String sku, final BigDecimal price, final String currency, final Date purchaseTime)
	{
		Handler handler = new Handler(context.getMainLooper());
		handler.post(new Runnable() {
			public void run() {
				AsyncTask<Void, Void, Void> task = new WorkerTask(context)
				{
					@Override
					protected void doWork(Context context)
					{
						try {
							DeviceFeature2_5.trackInAppRequest(context, sku, price, currency, purchaseTime);
						} catch (Exception e) {
						}
					}
				};

				ExecutorHelper.executeAsyncTask(task);
			}
		});
	}

	/**
	 * Gets asynchronous registration task
	 *
	 * @param context
	 * @param regId registration ID
	 * @return task that make registration asynchronously
	 */
	private AsyncTask<Void, Void, Void> getRegisterAsyncTask(final Context context, final String regId)
	{
		return new WorkerTask(context)
		{
			@Override
			protected void doWork(Context context)
			{
				DeviceRegistrar.registerWithServer(mContext, regId);
			}
		};
	}

	/**
	 * Cancels previous registration task
	 */
	private void cancelPrevRegisterTask()
	{
		synchronized (mSyncObj)
		{
			if (null != mRegistrationAsyncTask)
			{
				mRegistrationAsyncTask.cancel(true);
			}
			mRegistrationAsyncTask = null;
		}
	}

	/**
	 * Schedules a local notification
	 * @param context
	 * @param message notification message
	 * @param seconds delay (in seconds) until the message will be sent
	 */
	static public void scheduleLocalNotification(Context context, String message, int seconds)
	{
		scheduleLocalNotification(context, message, null, seconds);
	}

	/**
	 * Schedules a local notification with extras
	 *
	 * Extras parameters:
	 * title - message title, same as message parameter
	 * l - link to open when notification has been tapped
	 * b - banner URL to show in the notification instead of text
	 * u - user data
	 * i - identifier string of the image from the app to use as the icon in the notification
	 * ci - URL of the icon to use in the notification
	 *
	 * @param context
	 * @param message notification message
	 * @param extras notification extras parameters
	 * @param seconds delay (in seconds) until the message will be sent
	 */
	static public void scheduleLocalNotification(Context context, String message, Bundle extras, int seconds)
	{
		AlarmReceiver.setAlarm(context, message, extras, seconds);
	}

	/**
	 * Removes all scheduled local notifications
	 * @param context
	 */
	static public void clearLocalNotifications(Context context) {
		AlarmReceiver.clearAlarm(context);
	}
	
	static public Map<String, Object> incrementalTag(Integer value) {
		Map<String, Object> result = new HashMap<String, Object>();
		result.put("operation", "increment");
		result.put("value", value);
		
		return result;
	}
}
