//
//  PushHandlerActivity.java
//
// Pushwoosh Push Notifications SDK
// www.pushwoosh.com
//
// MIT Licensed

package com.arellomobile.android.push;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

public class PushHandlerActivity extends Activity
{
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);

        handlePush();
    }

    private void handlePush()
    {
        PushManager.onHandlePush(this);
        finish();
    }

    @Override
    protected void onNewIntent(Intent intent)
    {
        super.onNewIntent(intent);

        setIntent(intent);
        handlePush();
    }
}
