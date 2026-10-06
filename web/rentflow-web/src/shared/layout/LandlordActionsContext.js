import { createContext, useContext } from 'react'

export const LandlordActionsContext = createContext(null)
export const useLandlordActions = () => useContext(LandlordActionsContext)
