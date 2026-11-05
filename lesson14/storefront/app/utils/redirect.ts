// The ?redirect= target after login or register. Only same-site paths, so it cannot send the user to another origin.
export function redirectTarget(redirect: unknown): string {
  return typeof redirect === 'string' && redirect.startsWith('/') && !redirect.startsWith('//') ? redirect : '/'
}
