import { useState, useEffect } from 'react'

export default function App() {
  const [todos, setTodos] = useState([])
  const [text, setText] = useState('')

  const load = () =>
    fetch('/api/todos').then(r => r.json()).then(setTodos)

  useEffect(() => { load() }, [])

  const add = (e) => {
    e.preventDefault()
    if (!text.trim()) return
    fetch('/api/todos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: text.trim() })
    }).then(() => { setText(''); load() })
  }

  const remove = (id) =>
    fetch(`/api/todos/${id}`, { method: 'DELETE' }).then(load)

  const toggle = (t) =>
    fetch(`/api/todos/${t.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ done: !t.done })
    }).then(load)

  return (
    <div style={{ maxWidth: 480, margin: '40px auto', fontFamily: 'system-ui' }}>
      <h1>todos</h1>
      <form onSubmit={add} style={{ display: 'flex', gap: 8 }}>
        <input
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="what needs doing?"
          style={{ flex: 1, padding: 8, fontSize: 16 }}
        />
        <button type="submit" style={{ padding: '8px 16px', fontSize: 16 }}>add</button>
      </form>
      <ul style={{ listStyle: 'none', padding: 0, marginTop: 16 }}>
        {todos.map(t => (
          <li key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 0', borderBottom: '1px solid #eee' }}>
            <input type="checkbox" checked={t.done} onChange={() => toggle(t)} />
            <span style={{ flex: 1, textDecoration: t.done ? 'line-through' : 'none', color: t.done ? '#888' : '#000' }}>{t.text}</span>
            <button onClick={() => remove(t.id)} style={{ border: 'none', background: 'none', cursor: 'pointer', color: '#c00' }}>x</button>
          </li>
        ))}
      </ul>
      <p style={{ color: '#888', fontSize: 14 }}>{todos.length} items — powered by carp</p>
    </div>
  )
}
