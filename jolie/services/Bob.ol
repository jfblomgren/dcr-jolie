from lib.Endpoint import EndpointService, DummyInterface
from console import Console

interface BobInterface {
    requestResponse:
        WriteB(void)(void),
}

private service Impl {
    execution: concurrent

    embed EndpointService("Bob") as Endpoint
    embed Console as Console

    inputPort IP {
        location: "local"
        interfaces: BobInterface
        aggregates: Endpoint
    }

    main {
        [WriteB(void)(void) {
            println@Console("Wrote B to resource")()
        }]
    }
}

private interface extender EndpointExtension {
    requestResponse:
        *(void)(void) throws EventDisabled
}

service Bob {
    execution: concurrent

    embed Impl as Impl

    inputPort IP {
        location: "socket://localhost:8001"
        protocol: sodep
        interfaces: DummyInterface
        aggregates: Impl with EndpointExtension
    }

    courier IP {
        [WriteB(request)(response)] {
            before_event@Impl("WriteB")()
            forward(request)(response)
            after_event@Impl({ event_id = "WriteB", result << response })()
        }
    }

    main {
        [_(void)] {
            nullProcess
        }
    }
}