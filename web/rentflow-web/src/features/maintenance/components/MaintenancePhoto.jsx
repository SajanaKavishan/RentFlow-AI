import { useEffect, useState } from 'react'
import { getMaintenanceAttachmentDownload } from '../services/maintenanceApiService.js'

export default function MaintenancePhoto({ requestId, tenantId, attachment }) {
  const [source, setSource] = useState('')
  useEffect(() => {
    let active = true
    let objectUrl
    getMaintenanceAttachmentDownload(requestId, attachment.id, tenantId)
      .then((response) => response.blob())
      .then((blob) => {
        if (!active) return
        objectUrl = URL.createObjectURL(blob)
        setSource(objectUrl)
      }).catch(() => { /* The attachment can still be opened using its authorized action. */ })
    return () => {
      active = false
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [requestId, tenantId, attachment.id])
  return source ? <img className="maintenance-photo" src={source} alt={attachment.fileName} /> : null
}
