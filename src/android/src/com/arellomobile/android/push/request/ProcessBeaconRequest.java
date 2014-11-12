package com.arellomobile.android.push.request;

import android.content.Context;

import org.json.JSONException;

import java.util.Map;

public class ProcessBeaconRequest extends PushRequest
{
	public static final String CAME = "came";
	public static final String INDOOR = "indoor";
	public static final String CAME_OUT = "cameout";
	private String mProximityUuid;
	private String mMajor;
	private String mMinor;
	private String mAction;

	public ProcessBeaconRequest(String proximityUuid, String major, String minor, String action)
	{
		super();
		mProximityUuid = proximityUuid;
		mMajor = major;
		mMinor = minor;
		mAction = action;
	}

	public String getMethod() {
		return "processBeacon";
	}

	@Override
	protected void buildParams(Context context, Map<String, Object> params) throws JSONException
	{
		params.put("uuid", mProximityUuid.toUpperCase());
		params.put("major_number", mMajor);
		params.put("minor_number", mMinor);
		params.put("action", mAction);
	}
}
