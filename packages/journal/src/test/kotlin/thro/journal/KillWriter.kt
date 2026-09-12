package thro.journal

import thro.engine.Command

/**
 * The writer the test forks and kills. Writes visits for ever, one durable transaction each,
 * acknowledging after every commit.
 *
 * It is deliberately not a thread inside the test: a thread cannot be `SIGKILL`ed, and stopping one
 * politely would test the happy path. This has to be a process somebody can shoot.
 */
public fun main(args: Array<String>) {
    val path = args.first()
    val journal = Journal.open(path, DeviceId("kill-test"))
    val match = journal.createMatch(NewMatch("Kill", "Test"))
    var seq = 0
    while (true) {
        // 26 scores, is not a bust from 501, and never finishes a leg — so the engine accepts every
        // visit and the match never completes, which keeps the writer writing until it is shot.
        journal.append(Command.RecordVisit(Seat.HOME.playerId, 26), match.id)
        journal.append(Command.RecordVisit(Seat.AWAY.playerId, 26), match.id)
        seq += 2
        // Printed and flushed only after both commits returned. `println` on `System.out` flushes on
        // the newline for a console stream but not for a pipe, so the flush is explicit.
        println("KILLTEST-ACK $seq")
        System.out.flush()
    }
}
