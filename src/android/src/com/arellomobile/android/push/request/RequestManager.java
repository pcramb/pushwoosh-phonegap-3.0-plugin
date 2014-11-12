//
// RequestManager.java
//
// Pushwoosh Push Notifications SDK
// www.pushwoosh.com
//
// MIT Licensed
package com.arellomobile.android.push.request;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.Map;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.PackageManager.NameNotFoundException;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.Log;

import com.arellomobile.android.push.utils.JsonUtils;
import com.arellomobile.android.push.utils.PreferenceUtils;
import org.json.JSONException;
import org.json.JSONObject;

public class RequestManager
{
	private static final String META_NAME_PUSHWOOSH_URL = "PushwooshUrl";

	private static final String TAG = "Pushwoosh: Request manager";

	public static final int MAX_TRIES = 1;

	// due to lots of Android 2.2 not honoring updated GeoTrust certificate chain
	public static boolean useSSL = false;
	private static final String BASE_URL_SECURE = "https://cp.pushwoosh.com/json/1.3/";
	private static final String BASE_URL = "http://cp.pushwoosh.com/json/1.3/";
	
	private static Thread thread = null;
	private static ArrayList<PushRequest> requests = new ArrayList<PushRequest>(); 

	public static void sendRequest(final Context context, PushRequest request) throws Exception
	{
		//start thread if it is null
		synchronized(requests)
		{
			if(thread == null)
			{
				thread = new Thread()
				{
				    @Override
				    public void run()
				    {
				        try
				        {
				            while(true)
				            {
				                sleep(1000);
				                
				                PushRequest request = null;
				                Map<String, Object> data = null;
				                ArrayList<PushRequest> processingRequests = new ArrayList<PushRequest>();
				                
				                synchronized(requests)
				                {
					                if(requests.size() == 0)
					                	continue;
					                
					                request = requests.get(0);
					                processingRequests.add(request);
					                requests.remove(0);
					                
					                try
					                {
										data = request.getParams(context);
										
										for(int i = 0; i < requests.size(); ++i)
										{
											//make sure the requests are the same type
											PushRequest req = requests.get(i);
											if(req.getClass().isInstance(request))
											{
												//merge the request data
												Map<String, Object> dataToMerge = req.getParams(context);
												for (Map.Entry<String, Object> entry : dataToMerge.entrySet())
												{
													String key = entry.getKey();
													Object value = entry.getValue();
													
													if(value instanceof Map)
													{
														//merge inner map for setTags requests
														Map existingMap = (Map) data.get(key);
														if(existingMap != null && existingMap instanceof Map)
														{
															existingMap.putAll((Map)value);
															value = existingMap;
														}
														
														data.put(key, value);
													}
												}
												
												processingRequests.add(req);
												requests.remove(i);
												--i;
											}
										}
									} catch (JSONException e)
									{
										request.setException(e);
										continue;
									}
				                }
				                
								//send it
								JSONObject response = sendRequestInternal(context, data, request);
								for(PushRequest req : processingRequests)
								{
									if(response != null && req != request)
									{
										try
										{
											req.parseResponse(response);
										} catch (JSONException e) {
											req.setException(e);
										}
									}
									
									req.setProcessed();
								}
	
				            }
				        } catch (InterruptedException e) {
				            e.printStackTrace();
				            thread = null;
				        }
				    }
				};
				
				thread.start();
			}
		}
		
		if(!(request instanceof SetTagsRequest))
		{
			Map<String, Object> data = request.getParams(context);
			sendRequestInternal(context, data, request);

			Exception exception = request.getException();
			if(exception != null)
			{
				throw exception;
			}

			return;
		}
		
		synchronized(requests)
		{
			requests.add(request);
		}
		
		while(!request.isProcessed())
		{
			Thread.sleep(1000);
		}
		
		Exception exception = request.getException();
		if(exception != null)
		{
			throw exception;
		}
	}

	private static JSONObject sendRequestInternal(Context context, Map<String, Object> data, PushRequest request)
	{
		Log.w(TAG, "Try To sent: " + request.getMethod());

		NetworkResult res = new NetworkResult(500, 0, null);
		Exception exception = null;

		for (int i = 0; i < MAX_TRIES; ++i)
		{
			try
			{
				res = makeRequest(context, data, request.getMethod());
				if (200 != res.getResultCode())
				{
					continue;
				}

				if (200 != res.getPushwooshCode())
				{
					break;
				}

				Log.w(TAG, request.getMethod() + " response success");

				JSONObject response = res.getResultData();
				if (response != null)
				{
					// honor base url change
					if (response.has("base_url"))
					{
						String newBaseUrl = response.optString("base_url");
						PreferenceUtils.setBaseUrl(context, newBaseUrl);
					}

					request.parseResponse(response);
				}

				return response;
			}
			catch (Exception ex)
			{
				exception = ex;
			}
		}

		if(exception == null)
		{
			String message = "";
			if(res.getResultData() != null)
				message = res.getResultData().toString();
			
			exception = new Exception(message);
		}
		
		Log.e(TAG, "ERROR: " + exception.getMessage() + ". Response = " + res.getResultData(), exception);
		request.setException(exception);
		return null;
	}

	private static NetworkResult makeRequest(Context context, Map<String, Object> data, String methodName) throws Exception
	{
		NetworkResult result = new NetworkResult(500, 0, null);
		OutputStream connectionOutput = null;
		InputStream inputStream = null;
		try
		{
			// get the base url from preferences first
			String baseUrl = PreferenceUtils.getBaseUrl(context);
			if(TextUtils.isEmpty(baseUrl))
			{
				baseUrl = getDefaultUrl(context);
			}
			
			if (!baseUrl.endsWith("/"))
			{
				baseUrl += "/";
			}
			
			// save it
			PreferenceUtils.setBaseUrl(context, baseUrl);
			
			URL url = new URL(baseUrl + methodName);
			HttpURLConnection connection = (HttpURLConnection) url.openConnection();
			connection.setRequestMethod("POST");
			connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");

			connection.setDoOutput(true);

			JSONObject requestJson = new JSONObject();
			requestJson.put("request", JsonUtils.mapToJson(data));
			Log.w(TAG, "Pushwoosh Request: " + requestJson.toString());
			Log.w(TAG, "Pushwoosh Request To: " + (baseUrl + methodName));

			connection.setRequestProperty("Content-Length", String.valueOf(requestJson.toString().getBytes().length));

			connectionOutput = connection.getOutputStream();
			connectionOutput.write(requestJson.toString().getBytes());
			connectionOutput.flush();
			connectionOutput.close();

			inputStream = new BufferedInputStream(connection.getInputStream());

			ByteArrayOutputStream dataCache = new ByteArrayOutputStream();

			// Fully read data
			byte[] buff = new byte[1024];
			int len;
			while ((len = inputStream.read(buff)) >= 0)
			{
				dataCache.write(buff, 0, len);
			}

			// Close streams
			dataCache.close();

			String jsonString = new String(dataCache.toByteArray()).trim();
			Log.w(TAG, "Pushwoosh Result: " + jsonString);

			try
			{
				JSONObject resultJSON = new JSONObject(jsonString);
				result.setData(resultJSON);
				result.setCode(connection.getResponseCode());
				result.setPushwooshCode(resultJSON.getInt("status_code"));
			}
			catch(Exception e)
			{
				//reset base url
				PreferenceUtils.setBaseUrl(context, getDefaultUrl(context));		
				throw e;
			}
		}
		finally
		{
			if (null != inputStream)
			{
				inputStream.close();
			}
			if (null != connectionOutput)
			{
				connectionOutput.close();
			}
		}

		return result;
	}

	private static String getDefaultUrl(Context context)
	{
		String url = null;

		//Get Base URL from Metadata
		PackageManager packageManager = context.getPackageManager();
		try
		{
			ApplicationInfo info = packageManager.getApplicationInfo(context.getPackageName(), PackageManager.GET_META_DATA);
			Bundle metaData = info.metaData;
			if (metaData != null)
			{
				url = metaData.getString(META_NAME_PUSHWOOSH_URL);
			}
		}
		catch (NameNotFoundException e)
		{
			//nothing
		}

		if (TextUtils.isEmpty(url))
		{
			url = useSSL ? BASE_URL_SECURE : BASE_URL;
		}

		return url;
	}

	public static class NetworkResult
	{
		private int mPushwooshCode;
		private int mResultCode;
		private JSONObject mResultData;

		public NetworkResult(int networkCode, int pushwooshCode, JSONObject data)
		{
			mResultCode = networkCode;
			mPushwooshCode = pushwooshCode;
			mResultData = data;
		}

		public void setCode(int code)
		{
			mResultCode = code;
		}

		public void setPushwooshCode(int code)
		{
			mPushwooshCode = code;
		}

		public void setData(JSONObject data)
		{
			mResultData = data;
		}

		public int getResultCode()
		{
			return mResultCode;
		}

		public int getPushwooshCode()
		{
			return mPushwooshCode;
		}

		public JSONObject getResultData()
		{
			return mResultData;
		}
	}
}
