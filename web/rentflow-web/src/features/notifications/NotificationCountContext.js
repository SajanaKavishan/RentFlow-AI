import { createContext, useContext } from 'react'

export const NotificationCountContext = createContext(null)
export function useNotificationCount() { return useContext(NotificationCountContext) }
