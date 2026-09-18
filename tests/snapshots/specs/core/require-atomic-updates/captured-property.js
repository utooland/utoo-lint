const state = { count: 0 };
export async function update(task) {
  const previous = state.count;
  await task();
  state.count = previous + 1;
}
