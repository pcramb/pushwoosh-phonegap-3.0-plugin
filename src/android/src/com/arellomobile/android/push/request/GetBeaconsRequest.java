package com.arellomobile.android.push.request;

import org.json.JSONException;
import org.json.JSONObject;

public class GetBeaconsRequest extends PushRequest
{
	
	private JSONObject mResponse;

	public String getMethod() {
		return "getApplicationBeacons";
	}
	
	@Override
	public void parseResponse(JSONObject resultData) throws JSONException {
		mResponse = resultData.getJSONObject("response");
	}
	
	public JSONObject getResponse() {
		return mResponse;
	}
}
