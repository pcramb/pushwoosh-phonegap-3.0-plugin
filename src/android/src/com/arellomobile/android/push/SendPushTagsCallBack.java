package com.arellomobile.android.push;

import java.util.Map;

public interface SendPushTagsCallBack
{
	void taskStarted();

	void onSentTagsSuccess(Map<String, String> skippedTags);

	void onSentTagsError(Exception error);
}
