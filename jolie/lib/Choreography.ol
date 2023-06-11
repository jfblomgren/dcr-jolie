from runtime import Runtime

from .Evaluator import Expr, Evaluator

type EventID : string

type Event {
    id: EventID
    sender: string
    label: string
    receivers*: string
}

type Relation {
    source: EventID
    target: EventID
    guard: Expr
}

type Relations {
    conditions*: Relation
    responses*: Relation
    milestones*: Relation
    inclusions*: Relation
    exclusions*: Relation
    cancellations*: Relation
}

type Marking {
    executed*: EventID
    pending*: EventID
    included*: EventID
    values: undefined
}

type Choreography {
    events*: Event
    relations: Relations
    marking: Marking
}

type EventList {
    events*: Event
}

type ExecuteEventRequest {
    event_id: EventID
    result: undefined
}

interface ChoreographyInterface {
    RequestResponse:
        initialize(Choreography)(void),
        is_enabled(EventID)(bool),
        execute(ExecuteEventRequest)(void),
        get_value(EventID)(undefined)
}

type EventIDList {
    events*: EventID
}

type IsInRequest {
    events*: EventID
    id: EventID
}

type RemoveEventsRequest {
    events*: EventID
    remove*: EventID
}

type GetIncludedSourcesRequest {
    relations*: Relation
    included*: EventID
    values: undefined
    target: EventID
}

private interface ChoreographyHelperInterface {
    RequestResponse:
        is_in(IsInRequest)(bool),
        remove_events(RemoveEventsRequest)(EventIDList),
        get_included_sources(GetIncludedSourcesRequest)(EventIDList)
}

private service ChoreographyHelper {
    execution: concurrent

    embed Runtime as Runtime
    embed Evaluator as EvaluatorHelper
    
    inputPort Self {
        location: "local"
        interfaces: ChoreographyHelperInterface
    }

    outputPort Self {
        interfaces: ChoreographyHelperInterface
    }

    init {
        getLocalLocation@Runtime()(Self.location)
    }

    main {
        [is_in(req)(resp) {
            resp = false
            for (i = 0, i < #req.events && !resp, i++) {
                if (req.events[i] == req.id) {
                    resp = true
                }
            }
        }]

        [remove_events(req)(resp) {
            for (i = 0, i < #req.events, i++) {
                event << req.events[i]
                is_in@Self({
                    events << req.remove,
                    id << event
                })(should_remove)

                if (!should_remove) {
                    resp.events[#resp.events] << event
                }
            }
        }]

        [get_included_sources(req)(resp) {
            for (i = 0, i < #req.relations, i++) {
                relation << req.relations[i]
                if (relation.target == req.target) {
                    is_in@Self({
                        events << req.included,
                        id << relation.source
                    })(is_included)

                    if (is_included) {
                        evaluate@EvaluatorHelper({
                            expr << relation.guard,
                            values << req.values
                        })(guard_result)

                        if (guard_result) {
                            resp.events[#resp.events] << relation.source
                        }
                    }
                }
            }
        }]
    }
}

service ChoreographyService {
    execution: concurrent

    embed ChoreographyHelper as ChoreographyHelper
    embed Evaluator as Evaluator

    inputPort IP {
        location: "local"
        interfaces: ChoreographyInterface
    }

    main {
        [initialize(choreography)(void) {
            global.events << choreography.events
            global.marking << choreography.marking
            global.relations << choreography.relations

            for (i = 0, i < #global.events, i++) {
                event << global.events[i]
                global.events.by_id.(event.id) << event
            }
        }]

        [is_enabled(event_id)(result) {
            is_in@ChoreographyHelper({
                events << global.marking.included,
                id << event_id
            })(result)

            if (result) {
                get_included_sources@ChoreographyHelper({
                    relations << global.relations.conditions,
                    included << global.marking.included,
                    values << global.marking.values,
                    target << event_id
                })(included_sources)

                for (i = 0, i < #included_sources.events && result, i++) {
                    is_in@ChoreographyHelper({
                        events << global.marking.executed,
                        id << included_sources.events[i]
                    })(is_executed)

                    if (!is_executed) {
                        result = false
                    }
                }
            } 

            if (result) {
                undef(included_sources)
                get_included_sources@ChoreographyHelper({
                    relations << global.relations.milestones,
                    included << global.marking.included,
                    values << global.marking.values,
                    target << event_id
                })(included_sources)

                for (i = 0, i < #included_sources.events && result, i++) {
                    is_in@ChoreographyHelper({
                        events << global.marking.pending,
                        id << included_sources.events[i]
                    })(is_pending)

                    if (is_pending) {
                        result = false
                    }
                }
            } 
        }]

        [execute(req)(void) {
            global.marking.executed[#global.marking.executed] << req.event_id
            global.marking.values.(req.event_id) << req.result

            remove_events@ChoreographyHelper({
                events << global.marking.pending,
                remove[0] << req.event_id
            })(new_pending)
            undef(global.marking.pending)
            global.marking.pending << new_pending.events

            for (i = 0, i < #global.relations.cancellations, i++) {
                cancellation << global.relations.cancellations[i]
                if (cancellation.source == req.event_id) {
                    evaluate@Evaluator({
                        expr << cancellation.guard,
                        values << global.marking.values
                    })(guard_result)
                    if (guard_result) {
                        cancel[#cancel] << response.target
                    }
                }
            }

            remove_events@ChoreographyHelper({
                events << global.marking.pending,
                remove << cancel
            })(new_pending)

            undef(global.marking.pending)
            global.marking.pending << new_pending.events

            for (i = 0, i < #global.relations.responses, i++) {
                response << global.relations.responses[i]
                if (response.source == req.event_id) {
                    evaluate@Evaluator({
                        expr << response.guard,
                        values << global.marking.values
                    })(guard_result)
                    if (guard_result) {
                        global.marking.pending[#global.marking.pending] << response.target
                    }
                }
            }

            for (i = 0, i < #global.relations.exclusions, i++) {
                exclusion << global.relations.exclusions[i]
                if (exclusion.source == req.event_id) {
                    evaluate@Evaluator({
                        expr << exclusion.guard,
                        values << global.marking.values
                    })(guard_result)
                    if (guard_result) {
                        remove[#remove] << exclusion.target
                    }
                }
            }

            remove_events@ChoreographyHelper({
                events << global.marking.included,
                remove << remove
            })(new_included)
            undef(global.marking.included)
            global.marking.included << new_included.events

            for (i = 0, i < #global.relations.inclusions, i++) {
                inclusion << global.relations.inclusions[i]
                if (inclusion.source == req.event_id) {
                    evaluate@Evaluator({
                        expr << inclusion.guard,
                        values << global.marking.values
                    })(guard_result)

                    if (guard_result) {
                        global.marking.included[#global.marking.included] << inclusion.target
                    }
                }
            }
        }]

        [get_value(event_id)(value) {
            value = global.marking.values.(event_id)
        }]
    }
}