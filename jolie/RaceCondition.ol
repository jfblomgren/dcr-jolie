from console import Console
from json_utils import JsonUtils
from semaphore_utils import SemaphoreUtils
from time import Time

from services.Alice import AliceInterface
from services.Bob import BobInterface

service RaceCondition {
    embed Console as Console

    outputPort Alice {
        location: "socket://localhost:8000"
        protocol: sodep
        interfaces: AliceInterface
    }

    outputPort Bob {
        location: "socket://localhost:8001"
        protocol: sodep
        interfaces: BobInterface
    }

    main {
        scope (alice) {
            install(EventDisabled => println@Console("Alice is disabled")())
            WriteA@Alice()() 
        } | scope (bob) {
            install(EventDisabled => println@Console("Bob is disabled")())
            WriteB@Bob()()
        }
    }
}