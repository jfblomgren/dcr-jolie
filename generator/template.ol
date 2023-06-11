from lib.Endpoint import EndpointService, DummyInterface

interface {{ role }}Interface {
    requestResponse:
    {%- for event in events %}
        {{ event }}(void)(void),
    {%- endfor %}
}

private service Impl {
    execution: concurrent

    embed EndpointService("{{ role }}") as Endpoint

    inputPort IP {
        location: "local"
        interfaces: {{ role }}Interface
        aggregates: Endpoint
    }

    main {
        {%- for event in events %}
        [{{ event }}(void)(void) {
            nullProcess
        }]
        {%- endfor %}
    }
}

private interface extender EndpointExtension {
    requestResponse:
        *(void)(void) throws EventDisabled
}

service {{ role }} {
    execution: concurrent

    embed Impl as Impl

    inputPort IP {
        location: "{{ location }}"
        protocol: sodep
        interfaces: DummyInterface
        aggregates: Impl with EndpointExtension
    }

    courier IP {
    {%- for event in events %}
        [{{ event }}(request)(response)] {
            before_event@Impl("{{ event }}")()
            forward(request)(response)
            after_event@Impl({ event_id = "{{ event }}", result << response })()
        }
    {%- endfor %}
    }

    main {
        [_(void)] {
            nullProcess
        }
    }
}
