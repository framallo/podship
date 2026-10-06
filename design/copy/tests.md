# Copy: Test stage

| Key | en | es | Notes |
|---|---|---|---|
| tests.group | Tests | Pruebas | step group |
| tests.step | Run tests: {suite} | Run tests: {suite} | podship step title, not translated |
| tests.counts | {passed} passed · {failed} failed · {skipped} skipped | {passed} pasaron · {failed} fallaron · {skipped} omitidas | |
| tests.noCounts | Counts not available (exit code only) | Conteo no disponible (solo código de salida) | |
| tests.blocked | Blocked by tests. {count, plural, one{1 test failed} other{# tests failed}} in {suite}. Nothing was built or uploaded; {env} still runs {id}. | Bloqueado por pruebas. {count, plural, one{Falló 1 prueba} other{Fallaron # pruebas}} en {suite}. No se compiló ni se subió nada; {env} sigue con {id}. | |
| tests.next.title | What to do next | Qué hacer ahora | |
| tests.next.fix | Fix the tests and deploy again | Corregir las pruebas y desplegar de nuevo | text, not a button |
| tests.next.rerun | Run the tests again | Volver a correr las pruebas | for a flaky test |
| tests.next.skip | Deploy without tests… | Desplegar sin pruebas… | |
| tests.failing | Failing tests | Pruebas que fallan | |
| tests.output | Output | Salida | |
| skip.dialog.title | Deploy {project} to {env} without tests | Desplegar {project} a {env} sin pruebas | |
| skip.dialog.reason | Why are you skipping the tests? | ¿Por qué omites las pruebas? | label |
| skip.dialog.reasonHint | Saved with the release and shown in history. | Se guarda con la versión y aparece en el historial. | |
| skip.dialog.reasonError | Write why you're skipping the tests (at least 10 characters). It's saved with the release. | Escribe por qué omites las pruebas (al menos 10 caracteres). Se guarda con la versión. | on submit |
| skip.dialog.staging | The release is marked "Tests skipped" and can't be promoted to production without the same override. | La versión queda marcada como "Pruebas omitidas" y no se puede promover a production sin la misma excepción. | |
| skip.dialog.production | production only accepts releases whose tests passed. This override is recorded with your name and reason. | production solo acepta versiones cuyas pruebas pasaron. Esta excepción se registra con tu nombre y tu motivo. | |
| skip.dialog.confirm | Deploy to {env} without tests | Desplegar a {env} sin pruebas | |
| promote.tests.passed | Tests passed on {env}, {time}: {summary} | Las pruebas pasaron en {env}, {time}: {summary} | |
| promote.tests.refused | production accepts only releases whose tests passed. {id} has "{status}" on {env}. | production solo acepta versiones cuyas pruebas pasaron. {id} tiene "{status}" en {env}. | |
| promote.tests.ways | Deploy a fixed commit to {env} and promote it, or promote with an override. | Despliega un commit corregido a {env} y promuévelo, o promueve con una excepción. | |
| promote.tests.override | Promote without passed tests… | Promover sin pruebas aprobadas… | tier 2 |
| badge.passed | Tests passed | Pruebas aprobadas | |
| badge.failed | Tests failed | Pruebas fallidas | |
| badge.skipped | Tests skipped | Pruebas omitidas | reason on hover |
| badge.none | No tests | Sin pruebas | |
| suites.title | Test suites | Suites de pruebas | |
| suites.add | Add a suite | Agregar una suite | |
| suites.col | Name · Command · Directory · Timeout · Environments · Last result | Nombre · Comando · Carpeta · Tiempo límite · Entornos · Último resultado | |
| suites.dialog.title | Edit suite {name} | Editar la suite {name} | |
| suites.name.error | Use lowercase letters, digits and -. | Usa minúsculas, dígitos y -. | |
| suites.command.error | Write the command that runs the tests, for example dart test --reporter json. | Escribe el comando que corre las pruebas, por ejemplo dart test --reporter json. | |
| suites.dir.error | {dir} doesn't exist in {ref}. | {dir} no existe en {ref}. | |
| suites.timeout.error | Use a timeout between 1 and 120 minutes. | Usa un tiempo límite de 1 a 120 minutos. | |
| suites.env.error | Pick at least one environment. | Elige al menos un entorno. | |
| suites.saved | podship.yaml changed. Commit it with your next change. | podship.yaml cambió. Haz commit con tu próximo cambio. | |
