package com.arellomobile.android.push.request;

import java.math.BigDecimal;
import java.util.Date;
import java.util.Map;

import android.content.Context;

import org.json.JSONException;

/**
 * Date: 01.07.2014
 * Time: 19:56
 *
 * @author Yuri Shmakov
 */
public class TrackInAppRequest extends PushRequest
{
	private String mSku;
	private Date mPurchaseTime;
	private long mQuantity;
	private String mCurrency;
	private BigDecimal mPrice;

	public TrackInAppRequest(String sku, BigDecimal price, String currency, Date purchaseTime)
	{
		mSku = sku;
		mPurchaseTime = purchaseTime;
		mPrice = price;
		mCurrency = currency;
		
		mQuantity = 1;
	}

	@Override
	public String getMethod()
	{
		return "setPurchase";
	}

	@Override
	protected void buildParams(Context context, Map<String, Object> params) throws JSONException
	{
		params.put("productIdentifier", mSku);
		params.put("transactionDate", mPurchaseTime.getTime()/1000); //in seconds
		params.put("quantity", mQuantity);
		params.put("currency", mCurrency);
		params.put("price", mPrice);
	}
}
