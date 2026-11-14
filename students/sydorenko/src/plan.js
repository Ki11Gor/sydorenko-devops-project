const limits = {
  topics: [1, 365],
  perDay: [1, 50],
  minutes: [1, 240],
};

function createPlan(params) {
  const values = {};

  for (const [name, [min, max]] of Object.entries(limits)) {
    const entries = params.getAll(name);
    const [raw] = entries;
    const value = Number(raw);

    if (entries.length !== 1 || !/^\d+$/.test(raw) || value < min || value > max) {
      throw new RangeError(`${name} must be one integer between ${min} and ${max}`);
    }

    values[name] = value;
  }

  const { topics, perDay, minutes } = values;
  const days = Math.ceil(topics / perDay);
  const schedule = Array.from({ length: days }, (_, index) => {
    const dailyTopics = Math.min(perDay, topics - index * perDay);
    return { day: index + 1, topics: dailyTopics, minutes: dailyTopics * minutes };
  });

  return { topics, days, totalMinutes: topics * minutes, schedule };
}

module.exports = { createPlan };
