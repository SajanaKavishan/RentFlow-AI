import { useEffect, useState } from 'react'
import { getProfileImage } from './authApi.js'
import { initialsForName } from '../../shared/ui/userDisplay.js'

export default function ProfileAvatar({ user, className, previewUrl = null }) {
  const [loaded, setLoaded] = useState({ userId: '', url: null })
  const imageUrl = previewUrl || (loaded.userId === user.id ? loaded.url : null)

  useEffect(() => {
    if (!user.hasProfileImage || previewUrl) return undefined
    let active = true
    let objectUrl
    getProfileImage().then((blob) => {
      if (!active) return
      objectUrl = URL.createObjectURL(blob)
      setLoaded({ userId: user.id, url: objectUrl })
    }).catch(() => {
      if (active) setLoaded({ userId: user.id, url: null })
    })
    return () => {
      active = false
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [previewUrl, user.hasProfileImage, user.id])

  return <span className={className} aria-hidden="true">
    {imageUrl ? <img src={imageUrl} alt="" /> : initialsForName(user.fullName)}
  </span>
}
