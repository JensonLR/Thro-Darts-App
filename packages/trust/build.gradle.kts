plugins { kotlin("jvm") version "2.0.21" }

group = "thro-trust"
version = "1.0.0"
repositories { mavenCentral() }
dependencies {
    implementation("thro-engine:thro-engine")
    testImplementation(kotlin("test"))
}
kotlin { explicitApi() }
tasks.test {
    useJUnitPlatform()
    testLogging { showStandardStreams = true }
}
