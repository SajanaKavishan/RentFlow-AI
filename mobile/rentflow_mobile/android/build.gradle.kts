import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // Stripe assumes AGP 9 uses built-in Kotlin; Flutter 3.44 applies legacy KGP.
    // Keep its Kotlin bytecode target aligned with its Java 17 compile options.
    if (project.name == "stripe_android") {
        tasks.withType<KotlinJvmCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }

        // flutter_stripe 14.1.0 declares the optional issuing SDK both with and
        // without transitives. TapAndPay is not published in Google's Maven
        // repository, so keep the issuing SDK's intended non-transitive setup.
        configurations.configureEach {
            exclude(
                group = "com.google.android.gms",
                module = "play-services-tapandpay",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
