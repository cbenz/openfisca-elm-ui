module Requests exposing (..)

import Dict exposing (Dict)
import Http
import Json.Decode exposing (..)
import Json.Decode.Extra exposing (..)
import Json.Encode as Encode
import Types exposing (..)


-- ENCODERS


encodeGroupEntities : Dict String GroupEntity -> List ( String, Encode.Value )
encodeGroupEntities groupEntities =
    groupEntities
        |> Dict.toList
        |> List.map
            (\( entityId, roles ) ->
                ( entityId
                , Encode.list
                    [ Encode.object
                        (roles
                            |> Dict.toList
                            |> List.map
                                (\( roleId, individualIds ) ->
                                    ( roleId, encodeIndividualIds individualIds )
                                )
                        )
                    ]
                )
            )


encodeIndividualIds : List String -> Encode.Value
encodeIndividualIds individualIds =
    case List.head individualIds of
        Nothing ->
            Encode.list []

        Just firstIndividualId ->
            if List.length individualIds == 1 then
                Encode.string firstIndividualId
            else
                individualIds
                    |> List.map Encode.string
                    |> Encode.list


encodeInputValue : InputValue -> Encode.Value
encodeInputValue inputValue =
    case inputValue of
        BoolInputValue bool ->
            Encode.bool bool

        DateInputValue string ->
            Encode.string string

        EnumInputValue string ->
            Encode.string string

        FloatInputValue float ->
            Encode.float float

        IntInputValue int ->
            Encode.int int


encodeTestCase : List Individual -> Encode.Value
encodeTestCase individuals =
    Encode.object
        (( "individus"
           -- TODO Do not hardcode it
         , Encode.list
            (individuals
                |> List.indexedMap
                    (\index { inputValues } ->
                        Encode.object
                            (( "id", Encode.string (individualId index) )
                                :: (inputValues
                                        |> Dict.toList
                                        |> List.map
                                            (\( variableName, inputValue ) ->
                                                ( variableName, encodeInputValue inputValue )
                                            )
                                   )
                            )
                    )
            )
         )
            :: case groupEntities individuals of
                Nothing ->
                    []

                Just groupEntities ->
                    encodeGroupEntities groupEntities
        )



-- DECODERS


calculateValueDecoder : Decoder CalculateValue
calculateValueDecoder =
    dict (dict (list float))


entityDecoder : Decoder Entity
entityDecoder =
    -- TODO (list roleDecoder) does not work with optionalField
    -- create an issue at https://github.com/elm-community/json-extra
    -- (optionalField "roles" (dict roleDecoder)
    --     |> map (Maybe.map Dict.values >> Maybe.withDefault [])
    -- )
    succeed Entity
        |: (field "isPersonsEntity" bool |> withDefault False)
        |: (field "key" string)
        |: (field "label" string)
        |: (field "plural" string)
        |: (field "roles" (list roleDecoder) |> withDefault [])


roleDecoder : Decoder Role
roleDecoder =
    -- TODO (list string) does not work with optionalField
    -- create an issue at https://github.com/elm-community/json-extra
    -- (optionalField "subroles" (dict string)
    --     |> map (Maybe.map Dict.values >> Maybe.withDefault [])
    -- )
    succeed Role
        |: (field "key" string)
        |: (field "label" string)
        |: (maybe (field "max" int))
        |: (field "plural" string |> withDefault "")
        |: (field "subroles" (list string) |> withDefault [])


variableCommonFieldsDecoder : Decoder VariableCommonFields
variableCommonFieldsDecoder =
    succeed VariableCommonFields
        |: (field "entity" string)
        |: (maybe (field "label" string))
        |: (field "name" string)
        |: (field "source_code" string)
        |: (field "source_file_path" string)
        |: (field "start_line_number" int)
        |: (field "@type" string)


variableDecoder : Decoder Variable
variableDecoder =
    variableCommonFieldsDecoder
        |> andThen
            (\variableCommonFields ->
                case variableCommonFields.type_ of
                    "Boolean" ->
                        map BoolVariableFields
                            (field "default" bool)
                            |> map (\fields -> BoolVariable ( variableCommonFields, fields ))

                    "Date" ->
                        map DateVariableFields
                            (field "default" string)
                            |> map (\fields -> DateVariable ( variableCommonFields, fields ))

                    "Enumeration" ->
                        map2 EnumVariableFields
                            (field "default" string)
                            (field "labels" (dict string))
                            |> map (\fields -> EnumVariable ( variableCommonFields, fields ))

                    "Float" ->
                        map FloatVariableFields
                            (field "default" float)
                            |> map (\fields -> FloatVariable ( variableCommonFields, fields ))

                    "Integer" ->
                        map IntVariableFields
                            (field "default" int)
                            |> map (\fields -> IntVariable ( variableCommonFields, fields ))

                    _ ->
                        fail ("Unsupported type: " ++ variableCommonFields.type_)
            )


variablesResponseDecoder : Decoder VariablesResponse
variablesResponseDecoder =
    succeed VariablesResponse
        |: (field "country_package_name" string)
        |: (field "country_package_version" string)
        |: (field "currency" string)
        |: (field "variables"
                (list variableDecoder
                    |> map
                        (List.map
                            (\variable ->
                                ( variableCommonFields variable |> .name
                                , variable
                                )
                            )
                            >> Dict.fromList
                        )
                )
           )



-- REQUESTS


calculate : String -> List Individual -> Period -> Http.Request (Maybe CalculateValue)
calculate baseUrl individuals period =
    let
        body =
            Encode.object
                [ ( "scenarios"
                  , Encode.list
                        [ Encode.object
                            [ ( "test_case", encodeTestCase individuals )
                            , ( "period", Encode.string period )
                            ]
                        ]
                  )
                , ( "variables", Encode.list [ Encode.string "revenu_disponible" ] )
                , -- TODO parametrize
                  ( "output_format", Encode.string "variables" )
                ]
                |> Http.jsonBody
    in
        Http.post (baseUrl ++ "/1/calculate")
            body
            (field "value" (list calculateValueDecoder)
                |> map List.head
            )


entities : String -> Http.Request (Dict String Entity)
entities baseUrl =
    Http.get (baseUrl ++ "/2/entities") (field "entities" (dict entityDecoder))


variables : String -> Http.Request VariablesResponse
variables baseUrl =
    Http.get (baseUrl ++ "/1/variables") variablesResponseDecoder
