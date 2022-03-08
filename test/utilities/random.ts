export function getRandom(rnd: () => number, min: number, max: number) {
  const minL = Math.log(min);
  const maxL = Math.log(max);
  const v = rnd() * (maxL - minL) + minL;
  const res = Math.exp(v);
  console.assert(res <= max && res >= min, "Random value is out of the range");
  return res;
}

export function choice(rnd: () => number, object: { [key: string]: number }) {
  let total = 0;
  Object.entries(object).forEach(([_, p]) => (total += p));
  if (total <= 0) throw new Error("Error 62");
  const val = rnd() * total;
  let past = 0;
  for (let k in object) {
    past += object[k];
    if (past >= val) return k;
  }
  throw new Error("Error 70");
}

export function randBetween(min: number, max: number) {
  return Math.floor(Math.random() * (max - min)) + min;
}
