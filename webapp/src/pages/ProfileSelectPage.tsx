// Netflix-style "Wer schaut?" — port of app/lib/screens/profile_screen.dart.
// No direct equivalent in the Claude Design mock (app.jsx routes 'profile'
// to a bare Placeholder) — restyled with the same tokens/components instead.
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '../context/AuthContext'
import { createProfile, deleteProfile, getProfiles, updateProfile, type Profile } from '../api/profiles'
import { Modal } from '../components/common/Modal'
import { Icon } from '../components/layout/icons'
import { useCellFocus, useRegisterNav } from '../tv/FocusEngine'
import './ProfileSelectPage.css'

// Verified against app/lib/screens/profile_screen.dart:14-19.
const AVATAR_COLORS = ['#E50914', '#0071EB', '#E87C03', '#54B9C5', '#2CB67D', '#A259FF']
const LANGUAGES = ['German Dub', 'German Sub', 'English Dub', 'English Sub']

function AvatarButton({
  col,
  color,
  initial,
  label,
  onClick,
}: {
  col: number
  color: string
  initial: string
  label: string
  onClick: () => void
}) {
  const { isFocused, onHover } = useCellFocus(0, col)
  return (
    <button type="button" className={'profile-avatar' + (isFocused ? ' is-foc' : '')} onMouseEnter={onHover} onClick={onClick}>
      <span className="profile-avatar__circle" style={{ background: color }}>
        {initial}
      </span>
      <span className="text-body-md">{label}</span>
    </button>
  )
}

export function ProfileSelectPage() {
  const { selectProfile } = useAuth()
  const queryClient = useQueryClient()
  const { data: profiles } = useQuery({ queryKey: ['profiles'], queryFn: getProfiles })
  const [managing, setManaging] = useState(false)
  const [editing, setEditing] = useState<Profile | 'new' | null>(null)

  function invalidate() {
    return queryClient.invalidateQueries({ queryKey: ['profiles'] })
  }

  const count = (profiles?.length ?? 0) + 1

  useRegisterNav(
    [count, 1],
    (row, col) => {
      if (row === 1) {
        setManaging((m) => !m)
        return
      }
      if (col === count - 1) {
        setEditing('new')
        return
      }
      const p = profiles?.[col]
      if (!p) return
      if (managing) setEditing(p)
      else selectProfile(p.id)
    },
    [profiles?.length, managing],
  )
  const { isFocused: manageFocused, onHover: onManageHover } = useCellFocus(1, 0)

  return (
    <div className="profile-select">
      <div className="web-access__brand">
        <div className="brand-mark">
          <Icon name="play" w={22} />
        </div>
        <div className="brand-name">
          Red<b>Stream</b>
        </div>
      </div>
      <h1 className="text-display-md">Wer schaut?</h1>

      <div className="profile-select__grid">
        {profiles?.map((p, i) => (
          <AvatarButton
            key={p.id}
            col={i}
            color={p.avatar_color}
            initial={p.name.charAt(0).toUpperCase()}
            label={p.name}
            onClick={() => (managing ? setEditing(p) : selectProfile(p.id))}
          />
        ))}
        <AvatarButton col={count - 1} color="var(--panel-2)" initial="+" label="Hinzufügen" onClick={() => setEditing('new')} />
      </div>

      <button
        type="button"
        className={'filter' + (manageFocused ? ' is-foc' : '')}
        onMouseEnter={onManageHover}
        onClick={() => setManaging((m) => !m)}
      >
        {managing ? 'Fertig' : 'Profile verwalten'}
      </button>

      {editing && (
        <ProfileEditDialog
          profile={editing === 'new' ? null : editing}
          onClose={() => setEditing(null)}
          onSaved={invalidate}
        />
      )}
    </div>
  )
}

function ProfileEditDialog({
  profile,
  onClose,
  onSaved,
}: {
  profile: Profile | null
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(profile?.name ?? '')
  const [color, setColor] = useState(profile?.avatar_color ?? AVATAR_COLORS[0])
  const [language, setLanguage] = useState(profile?.default_language ?? '')

  async function save() {
    if (!name.trim()) return
    if (profile) {
      await updateProfile(profile.id, { name, avatar_color: color, default_language: language || null })
    } else {
      await createProfile({ name, avatar_color: color, default_language: language || null })
    }
    onSaved()
    onClose()
  }

  async function remove() {
    if (!profile) return
    await deleteProfile(profile.id)
    onSaved()
    onClose()
  }

  return (
    <Modal title={profile ? 'Profil bearbeiten' : 'Profil hinzufügen'} onClose={onClose}>
      <div className="profile-edit">
        <input className="text-input" value={name} onChange={(e) => setName(e.target.value)} placeholder="Name" autoFocus />
        <div className="profile-edit__swatches">
          {AVATAR_COLORS.map((c) => (
            <button
              key={c}
              type="button"
              className={`profile-edit__swatch${color === c ? ' profile-edit__swatch--active' : ''}`}
              style={{ background: c }}
              onClick={() => setColor(c)}
            />
          ))}
        </div>
        <div className="filters" style={{ padding: 0 }}>
          {LANGUAGES.map((lang) => (
            <button
              key={lang}
              type="button"
              className={`filter${language === lang ? ' on' : ''}`}
              onClick={() => setLanguage(lang === language ? '' : lang)}
            >
              {lang}
            </button>
          ))}
        </div>
        <div className="profile-edit__actions">
          {profile && (
            <button type="button" className="filter" onClick={remove}>
              Löschen
            </button>
          )}
          <button type="button" className="btn btn-primary" onClick={save}>
            Speichern
          </button>
        </div>
      </div>
    </Modal>
  )
}
