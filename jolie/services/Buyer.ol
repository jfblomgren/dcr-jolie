from lib.Endpoint import EndpointService, DummyInterface
from console import Console

interface BuyerInterface {
    requestResponse:
        Item(string)(void),
        Request(void)(string),
        Budget(int)(void),
        Order(void)(int),
}

private service Impl {
    execution: concurrent

    embed EndpointService("Buyer") as Endpoint
    embed Console as Console

    inputPort IP {
        location: "local"
        interfaces: BuyerInterface
        aggregates: Endpoint
    }

    main {
        [Item(item)(void) {
            println@Console("Setting item to " + item)()
            global.item = item
        }]
        [Request(void)(item) {
            println@Console("Requesting quote on " + global.item)()
            item = global.item
        }]
        [Budget(budget)(void) {
            println@Console("Setting budget to " + budget + "$")()
            global.budget = budget
        }]
        [Order(void)(amount) {
            get_value@Endpoint("Quote")(quote)
            amount = global.budget / quote
            println@Console("Ordering " + amount + " of " + global.item)()
        }]
    }
}

private interface extender EndpointExtension {
    requestResponse:
        *(void)(void) throws EventDisabled
}

service Buyer {
    execution: concurrent

    embed Impl as Impl

    inputPort IP {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: DummyInterface
        aggregates: Impl with EndpointExtension
    }

    courier IP {
        [Item(request)(response)] {
            before_event@Impl("Item")()
            forward(request)(response)
            after_event@Impl({ event_id = "Item", result << response })()
        }
        [Request(request)(response)] {
            before_event@Impl("Request")()
            forward(request)(response)
            after_event@Impl({ event_id = "Request", result << response })()
        }
        [Budget(request)(response)] {
            before_event@Impl("Budget")()
            forward(request)(response)
            after_event@Impl({ event_id = "Budget", result << response })()
        }
        [Order(request)(response)] {
            before_event@Impl("Order")()
            forward(request)(response)
            after_event@Impl({ event_id = "Order", result << response })()
        }
    }

    main {
        [_(void)] {
            nullProcess
        }
    }
}