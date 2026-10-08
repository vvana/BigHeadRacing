package com.darkmoonight.godotandroidyandexads;

// Android-плагин Godot для Yandex Mobile Ads SDK 8.x. Переписан 08.10.2026 с
// плагина noctisalamandra/godot-yandex-ads-android v1.3 (SDK 7.18.3): в 8.x
// убраны MobileAds (→ YandexAds), AdRequestConfiguration (→ AdRequest.Builder(id)),
// setAdLoadListener у загрузчиков (слушатель передаётся в loadAd) и
// BannerAdView.setAdUnitId. Имя синглтона, методы и сигналы сохранены — Ads.gd
// и addons/GodotAndroidYandexAds/yandex_ads.gd не меняются. AppMetrica убрана:
// игра зовёт init("") без неё.

import android.app.Activity;
import android.graphics.Color;
import android.util.ArraySet;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.yandex.mobile.ads.banner.BannerAdEventListener;
import com.yandex.mobile.ads.banner.BannerAdSize;
import com.yandex.mobile.ads.banner.BannerAdView;
import com.yandex.mobile.ads.common.AdError;
import com.yandex.mobile.ads.common.AdRequest;
import com.yandex.mobile.ads.common.AdRequestError;
import com.yandex.mobile.ads.common.ImpressionData;
import com.yandex.mobile.ads.common.YandexAds;
import com.yandex.mobile.ads.interstitial.InterstitialAd;
import com.yandex.mobile.ads.interstitial.InterstitialAdEventListener;
import com.yandex.mobile.ads.interstitial.InterstitialAdLoadListener;
import com.yandex.mobile.ads.interstitial.InterstitialAdLoader;
import com.yandex.mobile.ads.rewarded.Reward;
import com.yandex.mobile.ads.rewarded.RewardedAd;
import com.yandex.mobile.ads.rewarded.RewardedAdEventListener;
import com.yandex.mobile.ads.rewarded.RewardedAdLoadListener;
import com.yandex.mobile.ads.rewarded.RewardedAdLoader;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Set;

public class GodotAndroidYandexAds extends GodotPlugin {
    private static final String TAG = "godot";
    private final Activity activity;
    @Nullable
    private BannerAdView bannerAdView = null;
    @Nullable
    private RewardedAd rewardedAd = null;
    @Nullable
    private InterstitialAd interstitialAd = null;
    private FrameLayout layout = null;
    private FrameLayout.LayoutParams adParams = null;

    public GodotAndroidYandexAds(Godot godot) {
        super(godot);
        this.activity = getActivity();
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GodotAndroidYandexAds";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new ArraySet<>();
        signals.add(new SignalInfo("_on_banner_loaded"));
        signals.add(new SignalInfo("_on_banner_failed_to_load", Integer.class));
        signals.add(new SignalInfo("_on_banner_clicked"));
        signals.add(new SignalInfo("_on_banner_left_application"));
        signals.add(new SignalInfo("_on_returned_to_application_after_banner"));

        signals.add(new SignalInfo("_on_rewarded_video_ad_loaded"));
        signals.add(new SignalInfo("_on_rewarded_video_ad_failed_to_load", Integer.class));
        signals.add(new SignalInfo("_on_rewarded_video_ad_show"));
        signals.add(new SignalInfo("_on_rewarded_video_ad_failed_to_show", String.class));
        signals.add(new SignalInfo("_on_rewarded_video_ad_dismissed"));
        signals.add(new SignalInfo("_on_rewarded_video_ad_clicked"));
        signals.add(new SignalInfo("_on_rewarded", String.class, Integer.class));

        signals.add(new SignalInfo("_on_interstitial_loaded"));
        signals.add(new SignalInfo("_on_interstitial_failed_to_load", Integer.class));
        signals.add(new SignalInfo("_on_interstitial_ad_show"));
        signals.add(new SignalInfo("_on_interstitial_failed_to_show", String.class));
        signals.add(new SignalInfo("_on_interstitial_ad_dismissed"));
        signals.add(new SignalInfo("_on_interstitial_clicked"));
        return signals;
    }

    // apiKey (AppMetrica) принимается ради прежней сигнатуры и не используется.
    @UsedByGodot
    public void init(@NonNull final String apiKey) {
        YandexAds.initialize(activity, () -> Log.d(TAG, "YandexAds: SDK initialized, v" + YandexAds.getLibraryVersion()));
    }

    @UsedByGodot
    public void setAgeRestrictedUser(@NonNull final Boolean isAgeRestrictedUser) {
        YandexAds.setAgeRestricted(isAgeRestrictedUser);
    }

    @Override
    public View onMainCreate(Activity activity) {
        layout = new FrameLayout(activity);
        return layout;
    }

    // ---- баннер (игрой не используется, оставлен для полноты API) ----

    @NonNull
    private BannerAdSize getAdSize(int width, int height) {
        if (width > 0 && height > 0) {
            return BannerAdSize.fixed(activity, width, height);
        }
        DisplayMetrics displayMetrics = activity.getResources().getDisplayMetrics();
        int adWidthPixels = bannerAdView != null ? bannerAdView.getWidth() : displayMetrics.widthPixels;
        int adWidth = Math.round(adWidthPixels / displayMetrics.density);
        return BannerAdSize.sticky(activity, adWidth);
    }

    @NonNull
    private BannerAdView initBanner(final String id, final boolean isOnTop, int width, int height) {
        layout = (FrameLayout) activity.getWindow().getDecorView().getRootView();
        adParams = new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT);
        adParams.gravity = isOnTop ? Gravity.TOP : Gravity.BOTTOM;

        BannerAdView view = new BannerAdView(activity);
        view.setBackgroundColor(Color.TRANSPARENT);
        view.setAdSize(getAdSize(width, height));
        view.setBannerAdEventListener(createBannerAdEventListener());

        layout.addView(view, adParams);
        view.loadAd(new AdRequest.Builder(id).build());
        return view;
    }

    private BannerAdEventListener createBannerAdEventListener() {
        return new BannerAdEventListener() {
            @Override
            public void onAdLoaded() {
                Log.w(TAG, "YandexAds: onBannerAdLoaded");
                emitSignal("_on_banner_loaded");
            }

            @Override
            public void onAdFailedToLoad(@NonNull final AdRequestError error) {
                Log.w(TAG, "YandexAds: onBannerAdFailedToLoad. Error: " + error.getCode());
                emitSignal("_on_banner_failed_to_load", error.getCode());
            }

            @Override
            public void onAdClicked() {
                Log.w(TAG, "YandexAds: onBannerAdClicked");
                emitSignal("_on_banner_clicked");
            }

            @Override
            public void onImpression(@Nullable ImpressionData impressionData) {
            }
        };
    }

    @UsedByGodot
    public void loadBanner(final String id, final boolean isOnTop, int width, int height) {
        activity.runOnUiThread(() -> {
            if (bannerAdView == null) {
                bannerAdView = initBanner(id, isOnTop, width, height);
            } else {
                bannerAdView.loadAd(new AdRequest.Builder(id).build());
                Log.w(TAG, "YandexAds: Banner already created: " + id);
            }
        });
    }

    @UsedByGodot
    public void showBanner() {
        activity.runOnUiThread(() -> {
            if (bannerAdView != null) {
                bannerAdView.setVisibility(View.VISIBLE);
            } else {
                Log.w(TAG, "YandexAds: Banner not found");
            }
        });
    }

    @UsedByGodot
    public void removeBanner() {
        activity.runOnUiThread(() -> {
            if (layout == null || adParams == null) {
                return;
            }
            if (bannerAdView != null) {
                layout.removeView(bannerAdView);
                bannerAdView.destroy();
                bannerAdView = null;
            } else {
                Log.w(TAG, "YandexAds: Banner not found");
            }
        });
    }

    @UsedByGodot
    public void hideBanner() {
        activity.runOnUiThread(() -> {
            if (bannerAdView != null) {
                bannerAdView.setVisibility(View.GONE);
            } else {
                Log.w(TAG, "YandexAds: Banner not found");
            }
        });
    }

    // ---- ролик с вознаграждением («▶ ×2», «+500 за пару») ----

    @UsedByGodot
    public void loadRewardedVideo(final String id) {
        activity.runOnUiThread(() -> {
            try {
                RewardedAdLoader loader = new RewardedAdLoader(activity);
                loader.loadAd(new AdRequest.Builder(id).build(), new RewardedAdLoadListener() {
                    @Override
                    public void onAdLoaded(@NonNull RewardedAd ad) {
                        rewardedAd = ad;
                        Log.w(TAG, "YandexAds: onRewardedVideoAdLoaded");
                        emitSignal("_on_rewarded_video_ad_loaded");
                    }

                    @Override
                    public void onAdFailedToLoad(@NonNull AdRequestError error) {
                        Log.w(TAG, "YandexAds: onRewardedVideoAdFailedToLoad. Error: " + error.getCode() + " " + error.getDescription());
                        emitSignal("_on_rewarded_video_ad_failed_to_load", error.getCode());
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "YandexAds: loadRewardedVideo " + e);
            }
        });
    }

    @UsedByGodot
    public void showRewardedVideo() {
        activity.runOnUiThread(() -> {
            if (rewardedAd != null) {
                rewardedAd.setAdEventListener(createRewardedAdEventListener());
                rewardedAd.show(activity);
            } else {
                Log.w(TAG, "YandexAds: showRewardedVideo without loaded ad");
            }
        });
    }

    private RewardedAdEventListener createRewardedAdEventListener() {
        return new RewardedAdEventListener() {
            @Override
            public void onAdShown() {
                Log.w(TAG, "YandexAds: onRewardedVideoAdShown");
                emitSignal("_on_rewarded_video_ad_show");
            }

            @Override
            public void onAdFailedToShow(@NonNull AdError adError) {
                Log.w(TAG, "YandexAds: onRewardedVideoAdFailedToShow. Error: " + adError.getDescription());
                emitSignal("_on_rewarded_video_ad_failed_to_show", adError.getDescription());
            }

            @Override
            public void onAdDismissed() {
                Log.w(TAG, "YandexAds: onRewardedVideoAdDismissed");
                rewardedAd = null;   // ролик одноразовый — следующий показ требует новой загрузки
                emitSignal("_on_rewarded_video_ad_dismissed");
            }

            @Override
            public void onAdClicked() {
                emitSignal("_on_rewarded_video_ad_clicked");
            }

            @Override
            public void onAdImpression(@Nullable ImpressionData impressionData) {
            }

            @Override
            public void onRewarded(@NonNull Reward reward) {
                Log.w(TAG, "YandexAds: onRewarded " + reward.getType() + " " + reward.getAmount());
                emitSignal("_on_rewarded", reward.getType(), reward.getAmount());
            }
        };
    }

    // ---- межстраничная (игрой НЕ используется — решение игрока 23.09.2026) ----

    @UsedByGodot
    public void loadInterstitial(final String id) {
        activity.runOnUiThread(() -> {
            try {
                InterstitialAdLoader loader = new InterstitialAdLoader(activity);
                loader.loadAd(new AdRequest.Builder(id).build(), new InterstitialAdLoadListener() {
                    @Override
                    public void onAdLoaded(@NonNull InterstitialAd ad) {
                        interstitialAd = ad;
                        emitSignal("_on_interstitial_loaded");
                    }

                    @Override
                    public void onAdFailedToLoad(@NonNull AdRequestError error) {
                        emitSignal("_on_interstitial_failed_to_load", error.getCode());
                    }
                });
            } catch (Exception e) {
                Log.e(TAG, "YandexAds: loadInterstitial " + e);
            }
        });
    }

    @UsedByGodot
    public void showInterstitial() {
        activity.runOnUiThread(() -> {
            if (interstitialAd != null) {
                interstitialAd.setAdEventListener(createInterstitialAdEventListener());
                interstitialAd.show(activity);
            }
        });
    }

    private InterstitialAdEventListener createInterstitialAdEventListener() {
        return new InterstitialAdEventListener() {
            @Override
            public void onAdShown() {
                emitSignal("_on_interstitial_ad_show");
            }

            @Override
            public void onAdFailedToShow(@NonNull final AdError adError) {
                emitSignal("_on_interstitial_failed_to_show", adError.getDescription());
            }

            @Override
            public void onAdDismissed() {
                interstitialAd = null;
                emitSignal("_on_interstitial_ad_dismissed");
            }

            @Override
            public void onAdClicked() {
                emitSignal("_on_interstitial_clicked");
            }

            @Override
            public void onAdImpression(@Nullable final ImpressionData impressionData) {
            }
        };
    }
}
