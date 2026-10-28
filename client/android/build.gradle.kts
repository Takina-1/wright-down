allprojects {
    repositories {
        // Flutter engine artifacts belong to Flutter's repository, not Maven Central.
        exclusiveContent {
            forRepository {
                maven {
                    val storage = System.getenv("FLUTTER_STORAGE_BASE_URL")
                        ?: "https://storage.googleapis.com"
                    url = uri("$storage/download.flutter.io")
                }
            }
            filter { includeGroup("io.flutter") }
        }
        google()
        // HTTPS mirror for environments where Maven Central DNS is unavailable.
        maven("https://maven.aliyun.com/repository/central")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
