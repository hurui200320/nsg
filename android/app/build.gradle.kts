plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "info.skyblond.nsp"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "info.skyblond.nsp"
        // Support Android 7 (API 24)+ so an old spare phone can act as the GPS device
        minSdk = 24
        targetSdk = 36
        versionCode = 2
        versionName = "1.0.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // Release signing is opt-in via NSG_SIGN_RELEASE=true, set only by
    // .github/workflows/release.yml (job env, inherited by the Gradle step).
    // GITHUB_ACTIONS is deliberately NOT used as the gate: it is true for
    // every GitHub Actions run, so gating on it would force signing vars on
    // unrelated CI jobs (tests, lint, debug builds) and break fork PRs that
    // have no secrets. Local builds leave NSG_SIGN_RELEASE unset, so
    // signingConfig stays null below and any clean checkout builds an
    // unsigned APK without extra setup.
    // providers.environmentVariable keeps this configuration-cache safe.
    val signRelease = providers.environmentVariable("NSG_SIGN_RELEASE").orNull == "true"
    signingConfigs {
        create("release") {
            if (signRelease) {
                val keystorePath = providers.environmentVariable("KEYSTORE_PATH").orNull
                val storePassword = providers.environmentVariable("KEYSTORE_PASSWORD").orNull
                val keyAlias = providers.environmentVariable("KEY_ALIAS").orNull
                val keyPassword = providers.environmentVariable("KEY_PASSWORD").orNull
                if (keystorePath.isNullOrBlank() || storePassword.isNullOrBlank() || keyAlias.isNullOrBlank() || keyPassword.isNullOrBlank()) {
                    throw GradleException(
                        "Release signing env vars missing. " +
                            "Expected KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD " +
                            "when NSG_SIGN_RELEASE=true."
                    )
                }
                val ksFile = file(keystorePath)
                if (!ksFile.exists()) {
                    throw GradleException("Release keystore file not found at $keystorePath.")
                }
                storeFile = ksFile
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }
    buildTypes {
        release {
            // Signed only when NSG_SIGN_RELEASE=true via signingConfigs.release;
            // always unsigned otherwise so clones build with zero setup.
            // Output is app-release.apk when signed, app-release-unsigned.apk otherwise.
            signingConfig = if (signRelease) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            optimization {
                enable = false
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // java.time is used (ZonedDateTime/Instant/DateTimeFormatter) but only exists
        // on API 26+; desugar it so Android 7 (API 24) works as promised.
        isCoreLibraryDesugaringEnabled = true
    }
    buildFeatures {
        compose = true
    }
}

dependencies {
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.core)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    debugImplementation(libs.androidx.compose.ui.tooling)
}
