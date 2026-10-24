- `/go` now states a stop criterion for an operator-only obstacle (an access, an approval, a downed
  service): stop only when it blocks every remaining step; otherwise mark that step unverified, name it
  in the report, and finish the rest (dir #774).
