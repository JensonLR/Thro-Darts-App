plugins { kotlin("jvm") version "2.0.21" }
repositories { mavenCentral() }
dependencies { testImplementation(kotlin("test")) }
kotlin { explicitApi() }
tasks.test { useJUnitPlatform(); testLogging { showStandardStreams = true } }
