job("Build and push Docker") {
    // special step that runs a container with the Kaniko tool
    kaniko {
        // build an image
      	resources {
            cpu = 4.cpu
            memory = 4000.mb
        }
        build {
            dockerfile = "Dockerfile"
            // build-time variables
            // args["HTTP_PROXY"] = "http://10.20.30.2:1234"
            // image labels
            labels["vendor"] = "Deemos"
        }
        // push the image to a Space Packages repository (doesn't require authentication)
        push("packages.dev.deemos.com/p/hyperhuman/containers/lago-backend") {
            // image tags
            tags {
                +"1.0.\$JB_SPACE_EXECUTION_NUMBER"
                +"latest"
            }
        }
    }
}