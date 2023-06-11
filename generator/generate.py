import json
import sys

from jinja2 import Environment, FileSystemLoader

from choreography import Choreography

START_PORT = 8000

choreography = Choreography.parse_xml(sys.argv[1])
env = Environment(loader=FileSystemLoader("."))
locations = {
    role: f"socket://localhost:{START_PORT + port}"
    for port, role in enumerate(choreography.roles)
}

for cycle in choreography.get_cycles():
    print(
        f"[WARNING] Potential cycle detected: {' -> '.join(cycle + [cycle[0]])}"
    )


for role in choreography.roles:
    projection = choreography.project_for(role)

    endpoint_events = {
        event_id
        for event_id, event in projection.events.items()
        if role == event.sender
    }

    with open(f"services/{role}.ol", "w+") as f:
        f.write(
            env.get_template("template.ol").render(
                role=role,
                events=endpoint_events,
                location=locations[role],
            )
        )

    data = {
        "choreography": projection.serialize(),
        "dependencies": {
            event_id: choreography.serialize_dependencies(event_id)
            for event_id, event in choreography.events.items()
            if role == event.sender
        },
        "locations": locations,
    }

    with open(f"services/data/{role}.json", "w+") as f:
        f.write(json.dumps(data))
