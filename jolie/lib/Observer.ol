from .Choreography import EventID, ExecuteEventRequest

interface ObserverInterface {
    RequestResponse:
        notify(ExecuteEventRequest)(void)
}