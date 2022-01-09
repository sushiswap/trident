export function customError(errorName: string): string {
  return `VM Exception while processing transaction: reverted with custom error '${errorName}()'`;
}
