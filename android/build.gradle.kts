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
}

subprojects {
    val configureAndroid = {
        if (project.name != "app") {
            val android = project.extensions.findByName("android")
            if (android != null) {
                var currentSdk: Int? = null
                for (m in android.javaClass.methods) {
                    if (m.name == "getCompileSdkVersion" || m.name == "getCompileSdk") {
                        try {
                            val result = m.invoke(android)
                            if (result is Number) {
                                currentSdk = result.toInt()
                            } else if (result is String) {
                                currentSdk = result.replace("android-", "").toIntOrNull()
                            }
                            if (currentSdk != null) break
                        } catch (_: Exception) {}
                    }
                }
                // Only raise legacy compileSdk if below 36 (e.g. 31), never lower higher versions (e.g. 37)
                if (currentSdk != null && currentSdk < 36) {
                    for (m in android.javaClass.methods) {
                        if (m.name == "compileSdkVersion" || m.name == "setCompileSdkVersion" || m.name == "setCompileSdk") {
                            try {
                                m.invoke(android, 36)
                                break
                            } catch (_: Exception) {}
                        }
                    }
                }
            }
        }
    }
    if (state.executed) {
        configureAndroid()
    } else {
        afterEvaluate { configureAndroid() }
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
