# Orbital notes

> [!note] Why this matters
> A satellite's period depends only on the semi-major axis, not on its mass.

Kepler's third law, for a body orbiting a much heavier one:

$$
T = 2\pi \sqrt{\frac{a^3}{G M}}
$$

With $G M_\oplus \approx 3.986 \times 10^{14}\ \mathrm{m^3/s^2}$, the numbers work out as:

| Orbit | Altitude (km) | Period |
|---|---:|---:|
| ISS | 420 | 92.7 min |
| GPS | 20,200 | 11.97 h |
| Geostationary | 35,786 | 23.93 h |

```python
from math import pi, sqrt
def period(a_m, gm=3.986e14):
    return 2 * pi * sqrt(a_m**3 / gm)
```

- [x] Check the units
- [ ] Add the Moon
