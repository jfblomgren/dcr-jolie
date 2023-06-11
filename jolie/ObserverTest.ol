from lib.Observer import ObserverInterface
from lib.Subject import Subject
from lib.Endpoint import DummyInterface
from console import Console

service TestObserver {
    execution: concurrent

    embed Console as Console

    inputPort IP {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: ObserverInterface
    }

    main {
        [notify(req)(void) {
            println@Console("Event " + req.event_id + " was executed with value " + req.result)()
        }]
    }
}

service Test {
    embed Console as Console
    embed Subject as Subject

    main {
        subscribe@Subject({ observer = "socket://localhost:8000", event_id = "Test" })()
        send_notification@Subject({ event_id = "Test", result = 1 })()
        send_notification@Subject({ event_id = "NoSubscribers", result = 0 })()
    }
}