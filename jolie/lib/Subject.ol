from .Observer import ObserverInterface
from .Choreography import EventID, ExecuteEventRequest

type SubscriptionRequest {
    observer: string
    event_id: EventID
}

interface SubjectInterface {
    RequestResponse:
        subscribe(SubscriptionRequest)(void),
        send_notification(ExecuteEventRequest)(void)
}

service Subject {
    execution: concurrent

    inputPort IP {
        location: "local"
        interfaces: SubjectInterface
    }

    outputPort Observer {
        interfaces: ObserverInterface
        protocol: sodep
    }

    main {
        [subscribe(req)(void) {
            global.subscribers[#global.subscribers] << req
        }]

        [send_notification(req)(void) {
            for (i = 0, i < #global.subscribers, i++) {
                if (global.subscribers[i].event_id == req.event_id) {
                    Observer.location = global.subscribers[i].observer
                    notify@Observer(req)()
                }
            }
        }]
    }
}