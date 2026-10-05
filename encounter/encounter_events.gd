extends Node

@warning_ignore("unused_signal") # Emitted by encounter controllers through this event bus.
signal kaos_reached_klothis
@warning_ignore("unused_signal") # Emitted by encounter controllers through this event bus.
signal phase_two_started
@warning_ignore("unused_signal") # Emitted by encounter controllers through this event bus.
signal encounter_ended(reason: String)
