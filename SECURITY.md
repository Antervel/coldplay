# Security requirements

This software is intended for school children. It should be completely safe for them, and it will be supervised by a teacher.

## Banned subjects.
The list of banned subjects should be configurable, and would change depending on the age of the pupil and the subject (e.g. History vs. Anatomy). This is a partial list:
* Sexual themes.
* Explicit depiction of violence.
* ...TBD...

## Proposed security architecture.
* The chat will be handled by an AI model.
* Before showing the answer, a second AI model (the "censor") will check if the text adheres to the policy via prompting.
* A list of forbidden words will be filtered.
* A teacher will see the conversation live in their computers, and should be able to stop the interaction.

