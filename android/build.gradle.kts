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

open class FlutterFakeExtension {
    val compileSdkVersion: Int = 36
    val minSdkVersion: Int = 21
    val targetSdkVersion: Int = 34
    val ndkVersion: String = "26.1.10909125"
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    if (project.name != "app") {
        val flutterExt = FlutterFakeExtension()
        try {
            project.extensions.add("flutter", flutterExt)
        } catch (_: Throwable) {}
        project.extra.set("flutter", flutterExt)

        project.plugins.withId("com.android.library") {
            val android = project.extensions.findByName("android")
            if (android is org.gradle.api.plugins.ExtensionAware) {
                if (android.extensions.findByName("flutter") == null) {
                    android.extensions.add("flutter", flutterExt)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
