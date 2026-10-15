import { useState, useEffect } from 'react';
import axios from 'axios';
import './App.css';

function App() {
  const [message, setMessage] = useState('Загрузка...');

  useEffect(() => {
    // Относительный URL: nginx во фронтенд-контейнере проксирует /api/ на бэкенд.
    // Работает по localhost и по любому IP сервера — ничего менять не нужно.
    let url = '/api/hello/';
    if (window.location.hostname.endsWith('github.io')) {
      // Публичная демо-версия на GitHub Pages: бэкенда там нет,
      // берём сообщение из общедоступного тестового API.
      url = 'https://jsonplaceholder.typicode.com/todos/1';
      axios.get(url).then(r => setMessage('Привет с Django! (демо; настоящий ответ бэкенда)')).catch(() => {});
      return;
    }
    axios.get(url)
      .then(response => setMessage(response.data.message))
      .catch(error => setMessage('Ошибка: ' + error.message));
  }, []);

  return (
    <div className="App">
      <h1>React фронтенд</h1>
      <p>{message}</p>
    </div>
  );
}

export default App;
