;=====================================================================================
; Thomas W. Briggs and William G. Kennedy, 2016
; George Mason University, Fairfax, VA, USA
;
; Copyright 2016 Thomas W. Briggs
;
; Licensed under the Apache License, Version 2.0 (the “License”);
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;   http://www.apache.org/licenses/LICENSE-2.0
;
;
; Corresponding author contact:  Tom Briggs - tbriggs@gmu.edu
;
;
; IF YOU USE OR EXTEND THIS MODEL, PLEASE CITE AS
;
;   Briggs, T. W. & Kennedy, W. G. (2016). Active shooter: An agent-based model of unarmed resistance.
;     In 2016 Winter Simulation Conference (WSC) (pp. 3521-3531)
;
; Project details and paper available at:
;
;   http://bit.ly/shooterABM
;=====================================================================================


; BEGIN NETLOGO MODEL CODE

; Active-shooter scenario model

; Set up agents
breed [greens a-green] ; World will be mostly filled with greens
breed [blues a-blue]   ; Blues represent LEOs or soldiers in a peacekeeping function
breed [reds a-red]     ; Active shooter(s)
breed [green-bodies a-green-body] ; Green casualties
breed [blue-bodies a-blue-body]   ; Peacekeeper casualties
breed [red-bodies a-red-body]     ; Shooter casualties

globals [
  shots-fired          ; Boolean to track state of emergency
  count-shots          ; Shots taken counter
  count-hits           ; Counter for shots that hit individuals
  accuracy-slope       ; Slope of linear function to approximate hit probability as a function of distance between shooter and target
  to-safety            ; Number of agents who reach "safety" (aka the outer perimeter of the world)
  fighter-count        ; variable to hold the original number of fighters in the population
  struggles            ; variable to track the number of struggles with the shooter(s)
]

turtles-own [
  runningspeed         ; Running speeds (civilian, peacekeeper, or shooter) taken from Hayes and Hayes (2014) JASSS paper
  fighter?             ; Boolean to track whether agent will FIGHT rather than RUN
]

reds-own [
  shooter-magazine ;; magazine employed by shooter
  target           ;; individual shooter is focusing on in a given second (i.e., target)
]

greens-own [
  activated?  ;; Boolean to track whether a given green agent is "activated" (fight or flee)
  distance-to-shooter  ;; store distance to shooter at each tick
]

blues-own [
  distance-to-shooter
]

to setup
  clear-all
  ask patches [ set pcolor grey ]
  set-default-shape turtles "person"
  set-default-shape green-bodies "x"
  set-default-shape blue-bodies "x"
  set-default-shape red-bodies "x"

  create-greens population [
   ;; set color one-of [ 25 45 55 75 115 125 ]
    set color random 9 + 31
    set size 2.5
    set xcor random-xcor
    set ycor random-ycor ]

  calculate-hit-prob
  create-shooter

  ask greens [
    set activated? false
    set runningspeed random-normal 3.8923 2.7127          ;; converted from feet:  12.77 8.9 [CITATION: Hayes (2014)]
    if runningspeed < 0.3048 [ set runningspeed 0.3048 ]  ;; also converted from feet
    ifelse random-float 1.0 < %-who-fight [
      set fighter? TRUE
      set color yellow ]
      [ set fighter? FALSE ]
  ]
  set fighter-count count greens with [ fighter? = true ]

  ask blues [
    set runningspeed 6.60502                              ;; converted from feet per second:  21.67 [CITATION: Hayes (2014)]
    if runningspeed < 0.3048 [ set runningspeed 0.3048 ]
  ]
  reset-ticks
end

to go
  ;; STOP CONDITIONS
  if count red-bodies > 0 and count reds = 0 [ stop ]     ;; all active shooters have been neutralized
  if not any? greens [ stop ]
  if any? reds [
     shoot
  ]

  if count-shots > 0 and ticks = cognitive-delay [      ;; once shots fired, individuals realize they are in an active shooter scenario
    ask greens [ set activated? true ]
    ask greens [
    if not fighter? [
        if any? reds [
          face one-of reds
          rt 180 ;; turn away from the shooter to set heading
        ]
    ]
  ]
  ]
      ;; greens flee or fight the shooter
  ask greens [
    if activated? [
        ifelse fighter? [
          fight ]
          [ flee ]
        ]
  ]


  tick
end

to create-shooter
  repeat shooters [
    ask one-of patches [
      sprout-reds 1
      [set color red
       set size 3
       set shape "person"
       set shooter-magazine shooter-magazine-capacity]
    ]
  ]
end

to shoot
  ask reds [
        ;; MAGAZINE EMPTY - shooter pauses to reload at the end of every magazine (determined by user input mag capacity)
        ifelse (count-shots > 0) and (shooter-magazine = 0)
          [ reload ] ;; when zero cartridges remain in mag, shooter must reload and does not fire this turn (i.e., reload time is 1s)
        ;; ELSE catridges in mag, so proceed to shoot
          [

          ;; target selection
          set target nobody ;; clear out old target
          ifelse any? link-neighbors [ ;; check to see if anyone is struggling with me, if so, target them
            set target one-of link-neighbors
            facexy ( [xcor] of target ) ( [ycor] of target ) ]
            ;; ELSE if no one is struggling with shooter, he takes aim at nearest person
            [
            ;; IF VISUALIZE ENABLED - to visualize the target area - currently slows down the model a lot - too much CPU time
            if visualize? [
              let targetarea patches in-cone firearm-effective-range field-of-view
              let nontargetarea patches with [ not member? self targetarea ]
              ask targetarea [ set pcolor 3 ]
              ask nontargetarea [ set pcolor grey ]
            ] ;; END VISUALIZATION OF TARGET AREA

              if any? other turtles in-cone firearm-effective-range field-of-view with [ shape = "person" ] [
                let targetset other turtles in-cone firearm-effective-range field-of-view with [ shape = "person" ]
                set target min-one-of targetset [ distance myself ]
                  facexy ( [xcor] of target ) ( [ycor] of target )
              ]
            ;; type target print "target" ;; DEBUGGING print statement
            ]

          ;; end target selection

          ;; shot-kill action
          if target != nobody [ ; I have at least one target, with preference going to an agent I'm struggling with
            ifelse target = one-of link-neighbors [   ;; if a struggler, different hit probability
              let rand1 random-float 1.0
              if rand1 <= shooter-chance-of-overcoming-fighter [
                ask target [ become-casualty ]
              ]
            ]
            [ ;; ELSE (inner if else for whether target is in a struggle with me)
          if target != nobody [ ask target [ set shape "target" ] ]
          let dist distance target
          ;; calculate probability of hitting target as a function of distance from shooter to target.  Specifically:
          ;;   a linear function is calculated such that there is:
          ;;     100% chance of hitting target at point blank
          ;;      50% chance of hitting target at the firearm's effective range (i.e., range at which a practiced shooter hits target 50% of the time)
          ;;   further, the user can adjust the shooter's accuracy (due to poor skill, stress, etc) using the shot-accuracy parameter, implemented as a coefficient
          let percentchance ( ( ( accuracy-slope * dist + 100 ) / 100 ) * shot-accuracy )
          let rand random-float 1.0
          ifelse rand >= percentchance [ ;; greater than/equal to because if shooter MISSES intended target, might still hit someone else
            let tempagentset other turtles in-cone firearm-effective-range 1 with [ shape = "person" ] ;; and not target - NEED TO MAKE SURE TARGET ISN'T BEING KILLED
            if any? tempagentset [
              ask min-one-of tempagentset [ distance myself ] [
                become-casualty
              ;;  type who print "killed" - DEBUGGING print statement
              ]
            ]
           if target != nobody [ ask target [ set shape "person" ] ]
      ;;    set target nobody
          ] ;; end of IF
          ;; ELSE target is shot (accurately)
          [ ask target [ become-casualty ] ]
          ]
          ;; whether the shot hit a target or didn't, update trackers because the shooter had a target and fired
          ;; update trackers to count the shot fired this tick
          set count-shots count-shots + 1
          set shooter-magazine shooter-magazine - 1 ;; decrement magazine
          ]
        ;; end shot-kill action
        ]

      ] ;; closing bracket for outer IFELSE



end

to flee  ;; fleeing greens will run forward their runningspeed (note that direction set earlier)
    fd runningspeed

;  if (any? greens with [ fleeing ] in-radius 1) [
;      set heading ( [ heading ] of ( one-of greens in-radius 1 with [ fleeing ] ) )
;      fd 0.05
;  ]
  ;; fleeing agents reach "safety" at the perimeter of the world
  if abs (round xcor) = 50 [ become-safe ]
  if abs (round ycor) = 50 [ become-safe ]
end



to become-casualty
  if breed = greens [
    set breed green-bodies
    set shape "persondown"
    set heading random 360
   ;;  ask myself [ set target nobody ]
    ask my-links [ die ]
  ]
  if breed = blues
  [set breed blue-bodies
   set color blue ]
  if breed = reds
  [set breed red-bodies
   set color red
   set size 4 ]
  set count-hits count-hits + 1
end

to-report deaths
  show count green-bodies
end

to calculate-hit-prob  ;; solve for slope of line, assuming 100% hit at point-blank and 50% hit rate at user input effective range
                       ;; m = (y2-y1)/(x2-x1)
  set accuracy-slope (100 - 50) / ( 0 - firearm-effective-range )
end

to reload
  set shooter-magazine shooter-magazine-capacity
  ;; type "SHOOTER RELOADING - tick " print ticks
end

to fight
  if any? reds [
    let perp min-one-of reds [ distance myself ]
    let dist distance perp
    facexy ( [xcor] of perp) ( [ycor] of perp)
    ;; if shooter is close enough for me to tackle in less than 1s
    ifelse dist < [ runningspeed ] of self [
      create-link-with perp
      fd dist - 2  ;; using link to represent that someone is physically fighting the shooter
      struggle
      set struggles struggles + 1
    ]
    ;; otherwise shooter is not close enough to me, so I am running toward shooter
    [ fd runningspeed ]
  ]
end

to struggle
  let rand random-float 1.0
  if rand < chance-of-overcoming-shooter [
    ask one-of link-neighbors [ become-casualty ]
  ]
end

to update-distance
  if any? reds [
    set distance-to-shooter distance min-one-of reds [ distance myself ]
  ]
end

to add-hit
  set count-hits count-hits + 1
end

to become-safe
  set to-safety to-safety + 1
  die
end
@#$#@#$#@
GRAPHICS-WINDOW
421
10
1037
647
50
50
6.0
1
14
1
1
1
0
0
0
1
-50
50
-50
50
1
1
1
seconds
30.0

SLIDER
7
33
185
66
population
population
0
30000
5000
500
1
NIL
HORIZONTAL

SLIDER
7
149
150
182
shooters
shooters
1
1
1
1
1
NIL
HORIZONTAL

BUTTON
15
376
81
409
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
157
377
224
410
go 10
repeat 10 [ go ]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
238
377
301
410
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
6
186
222
219
shooter-magazine-capacity
shooter-magazine-capacity
10
30
10
1
1
rds
HORIZONTAL

SLIDER
6
294
184
327
field-of-view
field-of-view
20
180
180
10
1
degrees
HORIZONTAL

MONITOR
98
429
176
474
casualties
count green-bodies
17
1
11

MONITOR
4
429
94
474
rounds fired
count-shots
17
1
11

MONITOR
4
476
95
521
crowd density
precision (count turtles / count patches) 2
17
1
11

SLIDER
6
223
221
256
firearm-effective-range
firearm-effective-range
0
100
70
10
1
m
HORIZONTAL

TEXTBOX
12
133
162
151
SHOOTER (RED)
11
0.0
1

SLIDER
188
33
341
66
%-who-fight
%-who-fight
0
1
0.005
0.001
1
NIL
HORIZONTAL

MONITOR
98
523
176
568
# struggling
count links
17
1
11

BUTTON
88
377
151
410
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
6
258
178
291
shot-accuracy
shot-accuracy
0
1
0.8
0.1
1
NIL
HORIZONTAL

TEXTBOX
181
262
457
318
coefficient affecting hit probability - lessen accuracy at all ranges with this slider
11
0.0
1

SLIDER
7
68
179
101
cognitive-delay
cognitive-delay
0
5
3
1
1
secs
HORIZONTAL

TEXTBOX
9
18
159
36
POPULATION
11
0.0
1

SLIDER
188
68
411
101
chance-of-overcoming-shooter
chance-of-overcoming-shooter
0
1
0.01
0.01
1
NIL
HORIZONTAL

TEXTBOX
225
226
426
268
at this distance, a 100% accurate shooter hits target 50% of the time
11
0.0
1

PLOT
1051
18
1251
168
Casualties
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"heroes" 1.0 0 -1184463 true "" "plot count green-bodies with [ fighter? = true ]"
"innocents" 1.0 0 -10899396 true "" "plot count green-bodies with [ fighter? = false ]"
"peacekeepers" 1.0 0 -13345367 true "" "plot count blue-bodies with [ color = blue ]"

PLOT
1051
169
1251
319
Shots and Hits
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"shots" 1.0 0 -16777216 true "" "plot count-shots"
"hits" 1.0 0 -2674135 true "" "plot count-hits"

PLOT
1051
321
1251
471
Avg Distance from Shooter
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -10899396 true "" "if any? greens with [ fighter? = true ] [\n  plot mean [ distance-to-shooter ] of greens with [ fighter? = true ]\n]"
"pen-1" 1.0 0 -6459832 true "" "if any? greens with [ color = brown ] [\n  plot mean [ distance-to-shooter ] of greens with [ color = brown ]\n]"
"pen-2" 1.0 0 -13345367 true "" "if any? blues [\n  plot mean [ distance-to-shooter ] of blues\n]"

PLOT
1051
473
1251
623
Avg Running Speed
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -10899396 true "" "if any? greens [\n  plot mean [ runningspeed ] of greens\n]"
"casualties" 1.0 0 -2674135 true "" "if any? green-bodies [\n  plot mean [ runningspeed ] of green-bodies\n]"

SLIDER
6
330
266
363
shooter-chance-of-overcoming-fighter
shooter-chance-of-overcoming-fighter
0
1
0.5
0.1
1
NIL
HORIZONTAL

MONITOR
98
476
176
521
% to safety
precision (\n  to-safety / population\n)\n2\n* 100
17
1
11

MONITOR
178
523
304
568
% of fighters down
precision (\n  count green-bodies with [ fighter? = true ] / fighter-count\n)\n2\n* 100
17
1
11

SWITCH
188
294
304
327
visualize?
visualize?
1
1
-1000

TEXTBOX
309
304
459
322
(slows model a lot)
11
0.0
1

MONITOR
4
522
95
567
# fighters
count turtles with [ fighter? = true ]
17
1
11

MONITOR
178
429
247
474
accuracy
count green-bodies / count-shots
17
1
11

@#$#@#$#@
## LICENSE AND COPYRIGHT

   Copyright 2016 Thomas W. Briggs

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

## WHAT IS IT?

An agent-based model (ABM) of an active shooter scenario in which a mass shooter begins firing at nearby individuals in a crowd.

This model has applicability to both domestic and international security. The generalized landscape could represent a plaza, town square, or outdoor concert or event drawing a large crowd (e.g., inauguration).

In all of these situations, the identity and appearance of an active shooter is unknown and unpredictable.

Research questions of interest to be explored with the current model include:

*insights into the ratio of fighters needed to effectively neutralize an active shooter (and estimates of the number of casualties under various conditions)

It's envisioned that the model could be extended in a variety of ways to explore various security configurations to guard against an active shooter threat (e.g., snipers positioned in static locations).

## HOW IT WORKS

One or more shooters activates and begins firing on nearby victims.  Victims flee from the shooter.  The shooter assesses the area within his "vision" and continues targeting and firing on victims.

If enabled, a small percentage of "fighters" will attempt to resist the shooter.

1.  "Fighters" move toward the shooter.

2.  If a "fighter" is close enough to the shooter, he will attempt to tackle him, and a struggle ensues.  The user sets parameters to determine probabilities of the fighter overcoming the shooter or the shooter overcoming the fighter.

3.  The model run ends when either:
-The shooter is subdued by fighters.
-All victims either become casualties or escape the perimeter.

## EXTENDING THE MODEL

There are many ways the current model could be extended.  Some ideas:

CASUALTY SOPHISTICATION.  Currently, one round effectively hits one target.  A more sophisticated model might attempt to account for lethality of round-hits.

CROWD BEHAVIOR.  Currently, crowd behavior is modeled simply.  More sophisticated crowd behavior could be programmed.

LEO RESPONSE.  The model could be extended with the addition of LEOs / peacekeepers who take an active role in responding to an active shooter.  Some existing model code is already geared to this extension.

SPATIAL REPRESENTATION.  This model might also be adapted to better spatially represent the landscapes (e.g., schools) where active shooter scenarios seem to be common.  Giving fighters and victims cover or concealment would be a logical extension.

MULTIPLE SHOOTERS.  The impact of multiple shooters.

## RELATED MODELS

Rebellion model

## CREDITS AND REFERENCES

Hayes, Roy Lee, Hayes, Reginald Lee (2013, August 26). "Mass Shooting Simulation" (Version 1). CoMSES Computational Model Library. Retrieved from: https://www.openabm.org/model/3920/version/1

Hayes, Roy L, Hayes, Reginald L (2013, October 24). "Auroa Shooting Model" (Version 1). CoMSES Computational Model Library. Retrieved from: https://www.openabm.org/model/3993/version/1

Hayes, R., & Hayes, R. (2014). Agent-based simulation of mass shootings: Determining how to limit the scale of a tragedy. Journal of Artificial Societies and Social Simulation, 17(2), 5. Retrieved from: http://jasss.soc.surrey.ac.uk/17/2/5.html

## HOW TO CITE

If you extend this model or mention it in a publication, we ask that you include the following citation:

Briggs, T. W. & Kennedy, W. G. (2016). Active shooter: An agent-based model of unarmed resistance. In 2016 Winter Simulation Conference (WSC) (pp. 3521-3531)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

persondown
true
0
Circle -7500403 true true 5 110 80
Polygon -7500403 true true 90 195 195 180 285 210 300 195 300 165 225 150 300 135 300 105 285 90 195 120 90 105
Rectangle -7500403 true true 79 128 94 173
Polygon -7500403 true true 90 105 150 60 180 75 105 135
Polygon -7500403 true true 90 195 150 240 180 225 105 165
Circle -2674135 true false 101 116 67

personwcircle
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105
Circle -2674135 false false -31 -31 361

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.3.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
