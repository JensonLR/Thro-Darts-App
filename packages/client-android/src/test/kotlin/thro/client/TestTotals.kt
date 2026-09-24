package thro.client

/**
 * A total entered and, where it began on a finish, PD-001's questions answered "not sure" — which the
 * record keeps as unknown. For tests about something other than the questions.
 */
internal fun ThroSession.total(visit: Int) {
    enter(visit)
    while (prompt != null) answer(null)
}
