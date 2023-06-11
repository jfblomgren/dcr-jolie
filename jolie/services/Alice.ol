from lib.Endpoint import EndpointService, DummyInterface
from console import Console

interface AliceInterface {
    requestResponse:
        WriteA(void)(void),
}

private service Impl {
    execution: concurrent

    embed EndpointService("Alice") as Endpoint
    embed Console as Console

    inputPort IP {
        location: "local"
        interfaces: AliceInterface
        aggregates: Endpoint
    }

    main {
        [WriteA(void)(void) {
            println@Console("Wrote A to resource")()
        }]
    }
}

private interface extender EndpointExtension {
    requestResponse:
        *(void)(void) throws EventDisabled
}

service Alice {
    execution: concurrent

    embed Impl as Impl

    inputPort IP {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: DummyInterface
        aggregates: Impl with EndpointExtension
    }

    courier IP {
        [WriteA(request)(response)] {
            before_event@Impl("WriteA")()
            forward(request)(response)
            after_event@Impl({ event_id = "WriteA", result << response })()
        }
    }

    main {
        [_(void)] {
            nullProcess
        }
    }
}