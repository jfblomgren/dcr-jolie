from .Choreography import EventID, ChoreographyService, Choreography, ExecuteEventRequest
from .Subject import Subject, SubjectInterface
from .Observer import ObserverInterface

from semaphore_utils import SemaphoreUtils, SemaphoreUtilsInterface
from file import File

interface EndpointInterface {
    RequestResponse:
        before_event(EventID)(void) throws EventDisabled,
        after_event(ExecuteEventRequest)(void)
}

interface DummyInterface {
    oneWay:
        _(void)
}

service EndpointService(role: string) {
    execution: concurrent

    embed Subject as Subject
    embed ChoreographyService as Choreography
    embed SemaphoreUtils as Semaphores
    embed File as File

    inputPort IP {
        location: "local"
        interfaces: EndpointInterface, ObserverInterface
        aggregates: Subject, Choreography, Semaphores
    }

    outputPort Dependency {
        protocol: sodep
        interfaces: SemaphoreUtilsInterface
    }

    init {
        readFile@File({
            filename = "services/data/" + role + ".json",
            format = "json"
        })(data)

        initialize@Choreography(data.choreography)()
        global.locations << data.locations
        global.dependencies << data.dependencies

        for (i = 0, i < #data.choreography.events, i++) {
            undef(event)
            event << data.choreography.events[i]
            if (event.sender == role) {
                release@Semaphores({ name = event.id })()  // Create a semaphore

                for (j = 0, j < #event.receivers, j++) {
                    receiver << event.receivers[j]
                    subscribe@Subject({
                        observer = global.locations.(receiver),
                        event_id = event.id
                    })()
                }
            }
        }
    }

    main {
        [before_event(event_id)(void) {
            for (i = 0, i < #global.dependencies.(event_id), i++) {
                dep << global.dependencies.(event_id)[i]
                Dependency.location = global.locations.(dep.sender)
                acquire@Dependency({ name = dep.id })()

                if (dep.sender == role) {
                    is_enabled@Choreography(event_id)(enabled)
                    if (!enabled) {
                        for (j = i, j >= 0, j--) {
                            dep << global.dependencies.(event_id)[j]
                            Dependency.location = global.locations.(dep.sender)
                            release@Dependency({ name = dep.id })()
                        }

                        throw(EventDisabled)
                    }
                }
            }
        }]

        [after_event(request)(void) {
            send_notification@Subject(request)()

            for (i = 0, i < #global.dependencies.(request.event_id), i++) {
                dep << global.dependencies.(request.event_id)[i]
                Dependency.location = global.locations.(dep.sender)
                release@Dependency({ name = dep.id })()
            }
        }]

        [notify(req)(void) {
            execute@Choreography(req)()
        }]
    }
}