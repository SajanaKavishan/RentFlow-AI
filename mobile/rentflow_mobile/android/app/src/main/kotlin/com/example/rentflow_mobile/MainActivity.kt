package com.example.rentflow_mobile

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.AutocompleteSessionToken
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.api.net.FindAutocompletePredictionsRequest
import com.google.android.libraries.places.api.net.PlacesClient
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private var placesClient: PlacesClient? = null
    private var session: AutocompleteSessionToken? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rentflow/places")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "suggestTowns" -> suggestTowns(call, result)
                    "selectTown" -> selectTown(call, result)
                    "endSession" -> { session = null; result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun suggestTowns(call: MethodCall, result: MethodChannel.Result) {
        val query = call.argument<String>("query")?.trim().orEmpty()
        if (query.isEmpty()) { result.success(emptyList<Any>()); return }
        if (placesClient == null) {
            @Suppress("DEPRECATION")
            val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            val key = call.argument<String>("apiKey")?.trim().orEmpty().ifEmpty {
                info.metaData?.getString("com.rentflow.GOOGLE_PLACES_API_KEY").orEmpty().trim()
            }
            if (key.isEmpty()) {
                result.error("places_unconfigured", "Town suggestions are not configured.", null)
                return
            }
            Places.initializeWithNewPlacesApiEnabled(applicationContext, key, Locale.ENGLISH)
            placesClient = Places.createClient(this)
        }
        val token = session ?: AutocompleteSessionToken.newInstance().also { session = it }
        val request = FindAutocompletePredictionsRequest.builder()
            .setQuery(query)
            .setCountries(listOf("LK"))
            .setTypesFilter(listOf("(cities)"))
            .setSessionToken(token)
            .build()
        placesClient!!.findAutocompletePredictions(request)
            .addOnSuccessListener { response ->
                result.success(response.autocompletePredictions.map { prediction ->
                    mapOf("placeId" to prediction.placeId,
                        "town" to prediction.getPrimaryText(null).toString(),
                        "description" to prediction.getSecondaryText(null).toString())
                })
            }
            .addOnFailureListener { result.error("places_unavailable", "Town suggestions are unavailable.", null) }
    }

    private fun selectTown(call: MethodCall, result: MethodChannel.Result) {
        val client = placesClient
        val placeId = call.argument<String>("placeId")
        val fallback = call.argument<String>("fallbackTown").orEmpty()
        if (client == null || placeId.isNullOrBlank()) {
            result.error("places_unavailable", "Town selection is unavailable.", null)
            return
        }
        val token = session
        session = null
        val request = FetchPlaceRequest.builder(placeId, listOf(Place.Field.ID, Place.Field.ADDRESS_COMPONENTS))
            .setSessionToken(token).build()
        client.fetchPlace(request)
            .addOnSuccessListener { response ->
                val components = response.place.addressComponents?.asList().orEmpty()
                val city = listOf("locality", "postal_town", "administrative_area_level_2",
                    "administrative_area_level_3", "sublocality_level_1").firstNotNullOfOrNull { type ->
                    components.firstOrNull { it.types.contains(type) }?.name
                }
                result.success(city ?: fallback)
            }
            .addOnFailureListener { result.error("places_unavailable", "Town selection is unavailable.", null) }
    }
}
