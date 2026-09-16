package thro.rating

import kotlin.math.roundToInt

/**
 * What a person is shown (PD-105) — the projection layer the harness asks for at foundation, so the model choice
 * stays reversible. Three shapes and no fourth:
 *
 *  - [Unrated]: no qualifying match yet. Nothing is guessed.
 *  - [Provisional]: a range, rounded to tens, marked provisional. This is what anybody sees until the model has both
 *    the matches and the narrowness to say more — so a number at two matches, the harness's named failure, cannot
 *    be drawn.
 *  - [Established]: a whole number with the margin still beside it, once [Glicko2Model.ESTABLISH_AFTER] matches are
 *    counted and the deviation is under [Glicko2Model.ESTABLISHED_DEVIATION].
 *
 * A model with no dispersion (the shadow one) projects to [Unrated]: it has nothing it may show.
 */
public sealed interface Display {
    public data object Unrated : Display
    public data class Provisional(val low: Int, val high: Int, val matches: Int, val pool: Int) : Display
    public data class Established(val value: Int, val plusMinus: Int, val matches: Int, val pool: Int) : Display

    public companion object {
        public fun of(snapshot: Snapshot?, model: RatingModel): Display {
            if (snapshot == null || snapshot.rating == null || snapshot.dispersion == null || snapshot.matchesCounted == 0) return Unrated
            if (model.stage == RatingModel.Stage.SHADOW) return Unrated
            val r = snapshot.rating
            val d = snapshot.dispersion
            val narrow = d / 1.96 <= Glicko2Model.ESTABLISHED_DEVIATION
            return if (snapshot.matchesCounted >= Glicko2Model.ESTABLISH_AFTER && narrow) {
                Established(r.roundToInt(), d.roundToInt(), snapshot.matchesCounted, snapshot.pool)
            } else {
                Provisional(tens(r - d), tens(r + d), snapshot.matchesCounted, snapshot.pool)
            }
        }

        private fun tens(x: Double): Int = ((x / 10.0).roundToInt()) * 10
    }
}
