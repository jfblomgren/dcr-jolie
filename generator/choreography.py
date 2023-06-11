from __future__ import annotations

from dataclasses import dataclass, field, fields
from typing import Any, Generator, Optional, no_type_check
from xml.etree import ElementTree

from expr_parser import *

EventID = str
Role = str


class ProjectionException(Exception):
    ...


@dataclass
class Event:
    label: str
    sender: Role
    receivers: set[Role]

    def project(self, role: Role) -> Event:
        if role == self.sender:
            return self
        elif role in self.receivers:
            return Event(self.label, self.sender, {role})

        raise ProjectionException(f"{role} is not a participant in this event")

    def serialize(self, event_id: EventID) -> dict[str, Any]:
        return {
            "id": event_id,
            "label": self.label,
            "sender": self.sender,
            "receivers": list(self.receivers) + [self.sender],
        }

    @staticmethod
    @no_type_check
    def parse_xml(event: ElementTree.Element, 
                  label_mappings: ElementTree.Element) -> Event:
        label = label_mappings.find(
            f"labelMapping[@eventId='{event.get('id')}']"
        ).get("labelId")
        sender = event.findall("custom/roles/role")[0].text
        receivers = event.findall("custom/readRoles/readRole")
        receivers = set(
            receiver.text for receiver in receivers if receiver.text is not None
        )

        return Event(label, sender, receivers)


@dataclass(frozen=True)
class Relation:
    source: EventID
    target: EventID
    guard: Optional[Expression] = field(default=None)

    def serialize(self) -> dict[str, Any]:
        guard = serialize_expr(self.guard) if self.guard is not None else True
        return {"source": self.source, "target": self.target, "guard": guard}


@dataclass
class Relations:
    conditions: set[Relation] = field(default_factory=set)
    responses: set[Relation] = field(default_factory=set)
    milestones: set[Relation] = field(default_factory=set)
    inclusions: set[Relation] = field(default_factory=set)
    exclusions: set[Relation] = field(default_factory=set)
    cancellations: set[Relation] = field(default_factory=set)

    @staticmethod
    @no_type_check
    def parse_xml(root: ElementTree.Element) -> Relations:
        relations = root.find("specification/constraints")
        relations_store = Relations()

        expressions = root.find("specification/resources/expressions")

        for tag_name, field in {
            ("conditions", "conditions"),
            ("responses", "responses"),
            ("excludes", "exclusions"),
            ("includes", "inclusions"),
            ("milestones", "milestones"),
            ("coresponses", "cancellations"),
        }:
            for relation in relations.findall(f"{tag_name}/*"):
                source = relation.get("sourceId")
                target = relation.get("targetId")

                guard_id = relation.get("expressionId")
                if guard_id is not None:
                    guard = expressions.find(f"expression[@id='{guard_id}']")
                    guard = parse_expr(guard.get("value"))
                else:
                    guard = None

                relations_store.__dict__[field].add(
                    Relation(source, target, guard)
                )

        return relations_store

    def __iter__(self) -> Generator[Relation, None, None]:
        for field_ in fields(self):
            for relation in self.__dict__[field_.name]:
                yield relation

    @staticmethod
    def get_sources(
        relations: set[Relation], targets: set[EventID]
    ) -> set[EventID]:
        return set(rel.source for rel in relations if rel.target in targets)

    @staticmethod
    def contains(
        relations: set[Relation], source: EventID, target: EventID
    ) -> bool:
        return any(
            relation.source == source and relation.target == target
            for relation in relations
        )

    @no_type_check
    def project(self, events: set[EventID]) -> Relations:
        target_included = lambda relation: relation.target in events
        target_relation_exists = lambda relations, source: any(
            Relations.contains(relations, source, target) for target in events
        )

        return Relations(
            set(
                filter(
                    target_included,
                    self.conditions,
                )
            ),
            set(
                filter(
                    lambda response: target_included(response)
                    or target_relation_exists(
                        self.milestones, response.target
                    ),
                    self.responses,
                )
            ),
            set(
                filter(
                    target_included,
                    self.milestones,
                )
            ),
            set(
                filter(
                    lambda inclusion: target_included(inclusion)
                    or target_relation_exists(
                        self.conditions | self.milestones, inclusion.target
                    ),
                    self.inclusions,
                )
            ),
            set(
                filter(
                    lambda exclusion: target_included(exclusion)
                    or target_relation_exists(
                        self.conditions | self.milestones, exclusion.target
                    ),
                    self.exclusions,
                )
            ),
            set(
                filter(
                    lambda cancellation: target_included(cancellation)
                    or target_relation_exists(
                        self.milestones, cancellation.target
                    ),
                    self.cancellations,
                )
            ),
        )

    def serialize(self) -> dict[str, Any]:
        return {
            name: [relation.serialize() for relation in relations]
            for name, relations in self.__dict__.items()
        }


@dataclass
class Marking:
    executed: set[EventID] = field(default_factory=set)
    pending: set[EventID] = field(default_factory=set)
    included: set[EventID] = field(default_factory=set)
    values: dict[EventID, Any] = field(default_factory=dict)

    @staticmethod
    @no_type_check
    def parse_xml(root: ElementTree.Element) -> Marking:
        marking = root.find("runtime/marking")
        marking_store = Marking()

        for tag_name, field in {
            ("included", "included"),
            ("executed", "executed"),
            ("pendingResponses", "pending"),
        }:
            for event_xml in marking.findall(f"{tag_name}/event"):
                event = event_xml.get("id")
                marking_store.__dict__[field].add(event)

        for value in marking.findall("globalStore/variable"):
            converted_value = Marking._parse_value_xml(value)
            marking_store.values[value.get("id")] = converted_value

        return marking_store

    @staticmethod
    @no_type_check
    def _parse_value_xml(value):
        converters = {
            "int": int,
            "float": float,
            "string": str,
            "bool": lambda x: x == "true",
        }
        convert = converters[value.get("type")]
        return convert(value.get("value"))

    def project(
        self,
        events: set[EventID],
        projected_events: set[EventID],
        relations: Relations,
    ) -> Marking:
        include = (
            Relations.get_sources(relations.conditions, events)
            | Relations.get_sources(relations.milestones, events)
            | events
        )
        return Marking(
            self.executed & projected_events,
            self.pending & projected_events,
            (self.included & include) | (projected_events - include),
        )

    def serialize(self) -> dict[str, Any]:
        return {
            "executed": list(self.executed),
            "pending": list(self.pending),
            "included": list(self.included),
            "values": self.values,
        }


@dataclass
class Choreography:
    events: dict[EventID, Event] = field(default_factory=dict)
    relations: Relations = field(default_factory=Relations)
    marking: Marking = field(default_factory=Marking)

    @property
    def roles(self) -> set[Role]:
        roles = set()
        for event in self.events.values():
            roles.add(event.sender)
            roles |= event.receivers
        return roles

    @staticmethod
    @no_type_check
    def parse_xml(filename: str) -> Choreography:
        tree = ElementTree.parse(filename)
        root = tree.getroot()

        events = Choreography._parse_events_xml(root)
        relations = Relations.parse_xml(root)
        marking = Marking.parse_xml(root)
        choreography = Choreography(events, relations, marking)

        return choreography

    @staticmethod
    @no_type_check
    def _parse_events_xml(root: ElementTree.Element) -> dict[str, Event]:
        events = root.find("specification/resources/events")
        label_mappings = root.find("specification/resources/labelMappings")
        ids_to_events = {}

        for event_tree in events.findall("event"):
            event_id = event_tree.get("id")
            ids_to_events[event_id] = Event.parse_xml(event_tree, label_mappings)

        return ids_to_events

    def get_cycles(self) -> list[EventID]:
        edges = self.relations.conditions | self.relations.milestones
        visited = []
        path = []

        def visit(event_id: EventID) -> Optional[list[EventID]]:
            if event_id in visited:
                return None

            visited.append(event_id)
            path.append(event_id)

            result = None
            for edge in edges:
                if edge.source != event_id:
                    continue

                result = (
                    path.copy() if edge.target in path else visit(edge.target)
                )
                if result is not None:
                    break

            path.pop()
            return result

        return list(filter(lambda x: x is not None, map(visit, self.events)))

    def is_direct_dependency(self, source: EventID, target: EventID) -> bool:
        inclusions_exclusions = (
            self.relations.inclusions | self.relations.exclusions
        )
        conditions_milestones = (
            self.relations.conditions | self.relations.milestones
        )
        # Combines (4) and (5).
        responses_cancellations = (
            self.relations.responses | self.relations.cancellations
        )
        all_relations = (
            inclusions_exclusions
            | conditions_milestones
            | responses_cancellations
        )
        if source == target or Relations.contains(
            all_relations, source, target
        ):
            return True

        for event_id in self.events.keys():
            if (
                Relations.contains(inclusions_exclusions, source, event_id)
                and Relations.contains(conditions_milestones, event_id, target)
            ) or (
                Relations.contains(responses_cancellations, source, event_id)
                and Relations.contains(
                    self.relations.milestones, event_id, target
                )
            ):
                return True

        return False

    def delta_project(self, events: set[EventID]) -> Choreography:
        projected_events = {
            event_id: event
            for event_id, event in self.events.items()
            if any(
                self.is_direct_dependency(event_id, delta_event)
                for delta_event in events
            )
        }
        relations = self.relations.project(events)
        marking = self.marking.project(
            events, set(projected_events.keys()), self.relations
        )

        for relation in relations:
            if relation.guard is None:
                continue

            for event_id in get_identifiers(relation.guard):
                if event_id not in projected_events.keys():
                    raise ProjectionException(
                        "Guard refers to events that are not included in projection"
                    )

        return Choreography(projected_events, relations, marking)

    def project_for(self, role: Role) -> Choreography:
        receiver_events = {
            event_id: event
            for event_id, event in self.events.items()
            if role in event.receivers
        }
        initiator_events = {
            event_id
            for event_id, event in self.events.items()
            if role == event.sender
        }
        delta_proj = self.delta_project(initiator_events)
        delta_proj.marking.included |= receiver_events.keys() - (
            delta_proj.events.keys() - delta_proj.marking.included
        )

        proj_events = {
            event_id: event.project(role)
            for event_id, event in (
                receiver_events | delta_proj.events
            ).items()
        }

        return Choreography(
            proj_events,
            delta_proj.relations,
            delta_proj.marking,
        )

    def serialize_dependencies(
        self, event_id: EventID
    ) -> list[dict[str, Any]]:
        return [
            {"sender": dep.sender, "id": dep_id}
            for dep_id, dep in self.events.items()
            if self.is_direct_dependency(event_id, dep_id)
        ]

    def serialize(self) -> dict[str, Any]:
        return {
            "events": [
                event.serialize(event_id)
                for event_id, event in self.events.items()
            ],
            "marking": self.marking.serialize(),
            "relations": self.relations.serialize(),
        }
