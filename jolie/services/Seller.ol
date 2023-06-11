from lib.Endpoint import EndpointService, DummyInterface
from console import Console

interface SellerInterface {
    requestResponse:
        Quote(void)(int),
        Ship(void)(void),
}

private service Impl {
    execution: concurrent

    embed EndpointService("Seller") as Endpoint
    embed Console as Console

    inputPort IP {
        location: "local"
        interfaces: SellerInterface
        aggregates: Endpoint
    }

    main {
        [Quote(void)(price) {
            get_value@Endpoint("Request")(item)
            if (item == "Notepad") {
                price = 10
            } else if (item == "Pen") {
                price = 2
            } else if (item == "Eraser") {
                price = 1
            } else {
                price = -1 // Item not available
            }

            println@Console("Quoted buyer " + price + "$ for " + item)()
        }]
        [Ship(void)(void) {
            get_value@Endpoint("Order")(order)
            get_value@Endpoint("Request")(item)
            println@Console("Shipping " + order + " " + item + "(s) to buyer")()
        }]
    }
}

private interface extender EndpointExtension {
    requestResponse:
        *(void)(void) throws EventDisabled
}

service Seller {
    execution: concurrent

    embed Impl as Impl

    inputPort IP {
        location: "socket://localhost:8001"
        protocol: sodep
        interfaces: DummyInterface
        aggregates: Impl with EndpointExtension
    }

    courier IP {
        [Quote(request)(response)] {
            before_event@Impl("Quote")()
            forward(request)(response)
            after_event@Impl({ event_id = "Quote", result << response })()
        }
        [Ship(request)(response)] {
            before_event@Impl("Ship")()
            forward(request)(response)
            after_event@Impl({ event_id = "Ship", result << response })()
        }
    }

    main {
        [_(void)] {
            nullProcess
        }
    }
}