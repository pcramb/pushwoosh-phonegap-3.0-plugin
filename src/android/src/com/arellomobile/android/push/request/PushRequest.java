package com.arellomobile.android.push.request;

import android.content.Context;

import com.arellomobile.android.push.utils.GeneralUtils;
import com.arellomobile.android.push.utils.PreferenceUtils;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

public abstract class PushRequest {
	
	String response = "";
	private volatile boolean processed = false;
	private Exception exception = null;
	
	public abstract String getMethod();
	
	public final Map<String, Object> getParams(Context context) throws JSONException {
		Map<String, Object> baseParams = new HashMap<String, Object>();
		
		baseParams.put("application", PreferenceUtils.getApplicationId(context));
		baseParams.put("hwid", GeneralUtils.getDeviceUUID(context));
		baseParams.put("v", "1.0");	//SDK version

		buildParams(context, baseParams);

		return baseParams;
	}

	protected void buildParams(Context context, Map<String, Object> params) throws JSONException {
		// pass
	}
	
	public void parseResponse(JSONObject response) throws JSONException {
		if(response == null)
			return;
		
		this.response = response.toString();
	}
	
	public String getRawResponse() {
		return response;
	}

	public boolean isProcessed() {
		return processed;
	}
	
	public void setProcessed() {
		processed = true;
	}

	public void setException(Exception exception) {
		this.exception = exception;
	}
	
	public Exception getException() {
		return exception;
	}
}
